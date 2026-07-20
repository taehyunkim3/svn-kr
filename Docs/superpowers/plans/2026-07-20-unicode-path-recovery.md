# Unicode Path Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent NFC/NFD Korean path aliases from creating duplicate SVN add trees, present missing states accurately, and recover an already-corrupted working copy into a verified clean checkout without changing the original.

**Architecture:** `SVNWorkingCopySnapshot` parses one verbose status response into exact repository paths, NFC comparison keys, visible changes, revision range, and collapsed collisions. Commit preflight resolves new paths against exact versioned ancestors and rolls back only scheduling performed by that commit attempt. Recovery checks out into a user-selected empty directory, migrates only verified real changes, validates the destination snapshot, and registers it while preserving the source.

**Tech Stack:** Swift 6.2, Swift Concurrency, Foundation XMLParser/FileManager, SwiftUI, Swift Testing, SVN CLI 1.14.

## Global Constraints

- Preserve exact existing SVN path spelling; use NFC only for comparison, display, and genuinely new path components.
- Never edit `.svn/wc.db` directly and never silently revert an already-corrupted working copy.
- Keep the original recovery source and its files unchanged.
- Block commit before any local scheduling when a normalized path is ambiguous.
- Run `swift test` after every task and before completion.

---

### Task 1: Canonical path identity and working-copy snapshot

**Files:**
- Create: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Modify: `Sources/SVNCore/SVNXMLParser.swift`
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNCore/Models.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`

**Interfaces:**
- Produces: `SVNPathIdentity(rawPath:)`, `SVNPathCollision`, `SVNWorkingCopySnapshot`, `SVNXMLParser.workingCopySnapshot(from:)`, `SVNClient.workingCopySnapshot(at:credentials:)`.
- `SVNWorkingCopySnapshot` exposes `statuses`, `revision`, `collisions`, `hasPathCollisions`, and `resolvedPath(for:)`.

- [ ] **Step 1: Write failing canonical mapping tests**

```swift
@Test func resolvesDecomposedNewChildAgainstComposedVersionedAncestor() throws {
    let xml = snapshotXML(
        normal: ["00 사업관리"],
        changed: [("00 사업관리/새파일.xlsx".decomposedStringWithCanonicalMapping, "unversioned", nil)]
    )
    let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))
    #expect(snapshot.statuses.map(\.path) == ["00 사업관리/새파일.xlsx"])
    #expect(snapshot.resolvedPath(for: "00 사업관리/새파일.xlsx".decomposedStringWithCanonicalMapping) == "00 사업관리/새파일.xlsx")
}

@Test func collapsesMissingAddedAliasTreeIntoOneCollision() throws {
    let nfd = "04 구현".decomposedStringWithCanonicalMapping
    let xml = snapshotXML(
        normal: ["04 구현", "04 구현/기존.txt"],
        changed: [(nfd, "missing", "-1"), ("\(nfd)/하위", "missing", "-1")]
    )
    let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))
    #expect(snapshot.collisions.map(\.displayPath) == ["04 구현"])
    #expect(snapshot.collisions.first?.affectedEntryCount == 2)
    #expect(snapshot.statuses.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter SVNWorkingCopySnapshotTests`

Expected: compilation fails because `SVNWorkingCopySnapshot` and `workingCopySnapshot(from:)` do not exist.

- [ ] **Step 3: Implement path identity and snapshot parsing**

```swift
public struct SVNPathIdentity: Hashable, Sendable {
    public let rawPath: String
    public var canonicalKey: String { rawPath.precomposedStringWithCanonicalMapping }
    public var displayPath: String { canonicalKey }
}

public struct SVNPathCollision: Identifiable, Hashable, Sendable {
    public let canonicalPath: String
    public let rawPaths: [String]
    public let affectedEntryCount: Int
    public var id: String { canonicalPath }
    public var displayPath: String { canonicalPath }
}

public struct SVNWorkingCopySnapshot: Sendable {
    public let statuses: [SVNStatusEntry]
    public let revision: SVNWorkingCopyRevision
    public let collisions: [SVNPathCollision]
    public let versionedPathsByCanonicalKey: [String: [String]]
    public var hasPathCollisions: Bool { !collisions.isEmpty }
    public func resolvedPath(for rawPath: String) -> String
}
```

The parser must retain every verbose status record, build exact versioned-path groups by NFC key, remove `normal` records from visible changes, suppress `missing revision=-1` descendants beneath the shortest collision root, and prefer a versioned changed record over an equivalent `unversioned` alias.

- [ ] **Step 4: Make SVNClient fetch the snapshot with one command**

```swift
public func workingCopySnapshot(at path: String, credentials: SVNCredentials? = nil) async throws -> SVNWorkingCopySnapshot {
    let result = try checkedRun(["status", "--verbose", "--no-ignore", "--xml"], at: path, credentials: credentials)
    return try SVNXMLParser.workingCopySnapshot(from: Data(result.output.utf8))
}
```

Keep `status()` and `workingCopyRevision()` as compatibility wrappers over the snapshot until all callers migrate.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter SVNWorkingCopySnapshotTests`

Expected: PASS.

Run: `swift test`

Expected: all existing tests pass.

- [ ] **Step 6: Commit the snapshot layer**

```bash
git add Sources/SVNCore/SVNWorkingCopySnapshot.swift Sources/SVNCore/SVNXMLParser.swift Sources/SVNCore/SVNClient.swift Sources/SVNCore/Models.swift Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift
git commit -m "한글 SVN 경로 스냅샷 추가"
```

### Task 2: Accurate status labels, collision summary, and selection blocking

**Files:**
- Modify: `Sources/SVNCore/Models.swift`
- Modify: `Sources/SVNMac/ProjectDependencies.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Modify: `Sources/SVNMac/CommitControlsView.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`
- Test: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`

**Interfaces:**
- Consumes: `SVNWorkingCopySnapshot` from Task 1.
- Produces: `ProjectStore.pathCollisions`, `ProjectStore.canCommitSelectedPaths`, and `SVNStatusEntry.isMissingScheduledAddition`.

- [ ] **Step 1: Write failing store and source-contract tests**

```swift
@MainActor
@Test func refreshDropsMissingScheduledAdditionFromSelectionAndPublishesCollision() async {
    let collision = SVNPathCollision(canonicalPath: "04 구현", rawPaths: ["04 구현", "04 구현".decomposedStringWithCanonicalMapping], affectedEntryCount: 12)
    let client = StubSVNClient(snapshot: SVNWorkingCopySnapshot.fixture(statuses: [], collisions: [collision]))
    let store = makeStore(projects: [SVNProject(name: "p", path: "/tmp/p")], client: client)
    store.selectedPaths = ["04 구현"]
    await store.refresh()
    #expect(store.selectedPaths.isEmpty)
    #expect(store.pathCollisions == [collision])
    #expect(!store.canCommitSelectedPaths)
}
```

Add a source test requiring the Korean labels `삭제`, `로컬 누락`, `추가 취소됨`, and `한글 경로 충돌` and requiring `CommitControlsView` to use `store.selectableStatusPaths` for Select All.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter ProjectStoreTests`

Expected: compilation fails because the collision properties do not exist.

- [ ] **Step 3: Implement state semantics and UI**

```swift
public extension SVNStatusEntry {
    var isMissingScheduledAddition: Bool { item == .missing && (revision == nil || revision == "-1") }
    var isSelectableForCommit: Bool { !isMissingScheduledAddition && item != .ignored && item != .conflicted }
}
```

`ProjectStore.refresh()` must call `workingCopySnapshot`, assign `statuses`, `workingCopyRevision`, and `pathCollisions` atomically, and intersect selections with `selectableStatusPaths`. `ChangesView` must render one collision summary row per collision and use entry-aware label/color helpers. `CommitControlsView` must disable commit while collisions exist.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter ProjectStoreTests`

Expected: PASS.

Run: `swift test --filter ChangesViewPerformanceTests`

Expected: PASS.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit UI safety**

```bash
git add Sources/SVNCore/Models.swift Sources/SVNMac/ProjectDependencies.swift Sources/SVNMac/ProjectStore.swift Sources/SVNMac/ChangesView.swift Sources/SVNMac/CommitControlsView.swift Tests/SVNMacTests/ProjectStoreTests.swift Tests/SVNMacTests/ChangesViewPerformanceTests.swift
git commit -m "한글 경로 충돌 표시와 커밋 차단"
```

### Task 3: Commit preflight mapping and scheduling rollback

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNCore/Models.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Consumes: `SVNWorkingCopySnapshot.resolvedPath(for:)`.
- Produces: `SVNError.pathNormalizationCollision([String])` and rollback-safe `SVNClient.commit(...)`.

- [ ] **Step 1: Write failing command-log tests**

Create an injected SVN script returning a verbose snapshot with a composed normal parent and decomposed unversioned child. Assert `add` and `commit` receive the composed target. Add a second script where commit exits nonzero; assert the command log is `status`, `add`, `commit`, `revert` and the original command error is thrown. Add a collision snapshot and assert no `add`, `delete`, or `commit` command is logged.

```swift
#expect(lines.contains("add:00 사업관리/새파일.xlsx"))
#expect(lines.contains("revert:00 사업관리/새파일.xlsx"))
#expect(!lines.contains(where: { $0.hasPrefix("add:") }))
```

- [ ] **Step 2: Run the command tests and verify RED**

Run: `swift test --filter commit`

Expected: decomposed path is logged and no rollback occurs.

- [ ] **Step 3: Implement preflight and rollback**

At the beginning of `commit`, fetch one fresh snapshot. Throw `pathNormalizationCollision` before mutation when collisions exist. Resolve selected paths, classify by the resolved canonical path, schedule additions/deletions, and on commit failure run targeted `svn revert --depth infinity` only for paths scheduled by this invocation before rethrowing the original error.

```swift
do {
    return try checkedRunWithTargets(["commit", "--message", message], targets: commitTargets, at: path, credentials: credentials, allowUntrustedServerCertificate: allowUntrustedServerCertificate).output
} catch {
    if !scheduledTargets.isEmpty {
        _ = try? checkedRunWithTargets(["revert", "--depth", "infinity"], targets: scheduledTargets, at: path, credentials: nil)
    }
    throw error
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter commit`

Expected: PASS.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit transaction safety**

```bash
git add Sources/SVNCore/SVNClient.swift Sources/SVNCore/Models.swift Tests/SVNCoreTests/SVNCredentialsTests.swift
git commit -m "SVN 커밋 경로 자동 매핑과 실패 복구"
```

### Task 4: Safe side-by-side working-copy recovery

**Files:**
- Create: `Sources/SVNCore/SVNWorkingCopyRecovery.swift`
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNMac/ProjectDependencies.swift`
- Create: `Sources/SVNMac/ProjectStore+Recovery.swift`
- Create: `Sources/SVNMac/WorkingCopyRecoveryView.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopyRecoveryTests.swift`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Produces: `SVNRecoveryPreview`, `SVNRecoveryResult`, `SVNClient.recoveryPreview(at:)`, `SVNClient.recoverWorkingCopy(from:to:credentials:allowUntrustedServerCertificate:)`, and `ProjectStore.beginPathRecovery()`.

- [ ] **Step 1: Write failing filesystem recovery tests**

Build a temporary source with a snapshot fixture and a fake checkout command that creates a clean destination. Verify modified and genuinely new files are copied to NFC-resolved paths, false alias statuses are excluded, deleted files are removed only in the destination, the source hashes do not change, and a nonempty destination is rejected.

```swift
#expect(try Data(contentsOf: recoveredModified) == modifiedData)
#expect(FileManager.default.fileExists(atPath: sourceModified.path))
#expect(!FileManager.default.fileExists(atPath: recoveredDeleted.path))
#expect(result.snapshot.collisions.isEmpty)
```

- [ ] **Step 2: Run recovery tests and verify RED**

Run: `swift test --filter SVNWorkingCopyRecoveryTests`

Expected: compilation fails because recovery types and methods do not exist.

- [ ] **Step 3: Implement recovery planner and executor**

`SVNRecoveryPreview` must list composed source-to-destination mappings, modified/new/deleted counts, ignored alias count, and blocking conflicts. `recoverWorkingCopy` must require an empty destination, obtain the exact repository URL with `svn info --show-item url`, checkout the destination, copy only normalized top-level candidate paths, reproduce intended deletions in the destination, fetch a destination snapshot, and fail unless it has no path collisions.

```swift
public struct SVNRecoveryResult: Sendable {
    public let destinationPath: String
    public let snapshot: SVNWorkingCopySnapshot
    public let migratedPaths: [String]
}
```

- [ ] **Step 4: Implement the recovery sheet and project registration**

The collision summary exposes `경로 자동 복구…`. The sheet shows preview counts and asks the user to choose an empty destination folder. On success, create a security-scoped bookmark, append a new `SVNProject` using the source credentials/settings, select it, refresh it, and leave the source project registered and untouched.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter SVNWorkingCopyRecoveryTests`

Expected: PASS.

Run: `swift test --filter ProjectStoreTests`

Expected: PASS.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 6: Commit recovery**

```bash
git add Sources/SVNCore/SVNWorkingCopyRecovery.swift Sources/SVNCore/SVNClient.swift Sources/SVNMac/ProjectDependencies.swift Sources/SVNMac/ProjectStore+Recovery.swift Sources/SVNMac/WorkingCopyRecoveryView.swift Sources/SVNMac/ChangesView.swift Sources/SVNMac/ProjectStore.swift Tests/SVNCoreTests/SVNWorkingCopyRecoveryTests.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "손상된 한글 경로 작업 복사본 자동 복구"
```

### Task 5: Regression verification and documentation

**Files:**
- Modify: `README.md`
- Modify: `Docs/LayoutArchitecture.md` only if the recovery sheet introduces a new size/state contract.

**Interfaces:**
- Consumes all earlier tasks.
- Produces user documentation for automatic mapping, collision blocking, and recovery.

- [ ] **Step 1: Document the final behavior**

Document that existing server spelling wins, new path components use NFC, unambiguous aliases are automatic, ambiguous collisions block commit, and recovery preserves the original folder.

- [ ] **Step 2: Run formatting and full verification**

Run: `git diff --check`

Expected: no output.

Run: `swift test`

Expected: all tests pass with zero failures.

Run: `swift build -c release`

Expected: exit code 0.

- [ ] **Step 3: Inspect final repository scope**

Run: `git status --short --branch`

Expected: only the implementation and documentation paths listed in this plan are modified.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md Docs/LayoutArchitecture.md
git commit -m "한글 SVN 경로 복구 사용법 추가"
```
