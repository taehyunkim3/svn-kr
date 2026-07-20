# Canonical Alias In-Place Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Treat NFC-equivalent Korean paths as one logical path, remove only erroneous NFD SVN scheduling metadata in place, and commit real files through the repository's exact managed path without renaming local files.

**Architecture:** `SVNWorkingCopySnapshot` marks an orphaned `missing revision=-1` alias as repairable only when its NFC key maps to exactly one versioned repository path. `SVNClient` revalidates and reverts those exact raw alias roots without `--remove-added`, then refreshes the snapshot before path mapping and commit. SwiftUI invokes in-place repair directly for repairable aliases and keeps the side-by-side recovery sheet only for genuinely ambiguous repository paths.

**Tech Stack:** Swift 6.2, Swift Concurrency, Foundation XMLParser/FileManager, SwiftUI, Swift Testing, SVN CLI 1.14.

## Global Constraints

- Never rename, move, overwrite, or delete the user's local files during alias repair.
- Never pass `--remove-added` to `svn revert`.
- Preserve the exact existing repository path spelling; use NFC only for comparison, display, and genuinely new path components.
- Re-read the verbose working-copy snapshot immediately before every mutating repair or commit command.
- Do not mutate `.svn/wc.db` directly.
- Preserve unrelated user changes and stage only files listed by the current task.
- Run focused tests after every RED/GREEN cycle and `swift test` before completion.

---

### Task 1: Expose Repairable Canonical Alias Roots

**Files:**
- Modify: `Sources/SVNCore/SVNWorkingCopySnapshot.swift`
- Test: `Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift`

**Interfaces:**
- Consumes: `SVNWorkingCopyEntry`, `SVNPathCollision`, and the existing NFC `canonicalKey` grouping.
- Produces: `SVNPathCollision.repairableRawPath: String?`, `SVNWorkingCopySnapshot.repairableAliasPaths: [String]`, and `SVNWorkingCopySnapshot.hasUnrepairablePathCollisions: Bool`.

- [ ] **Step 1: Write failing snapshot tests**

Add tests that parse one NFC versioned root and three NFD `missing revision=-1` descendants. Require the shortest exact NFD root to be repairable even when equivalent unversioned files exist. Add a second test with two versioned raw paths sharing one NFC key and require no repairable path.

```swift
#expect(snapshot.repairableAliasPaths.map { Data($0.utf8) } == [Data(nfdRoot.utf8)])
#expect(!snapshot.hasUnrepairablePathCollisions)

#expect(ambiguous.repairableAliasPaths.isEmpty)
#expect(ambiguous.hasUnrepairablePathCollisions)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter SVNWorkingCopySnapshotTests`

Expected: compilation fails because `repairableAliasPaths` and `hasUnrepairablePathCollisions` do not exist.

- [ ] **Step 3: Implement minimal repair metadata**

Extend `SVNPathCollision` with an optional exact raw repair target. When creating an orphaned collision, set it only if `versionedPathsByCanonicalKey[canonicalPath]?.count == 1`. Preserve raw bytes with `Data(path.utf8)` and keep the shortest orphan root.

```swift
public let repairableRawPath: String?

public var repairableAliasPaths: [String] {
    collisions.compactMap(\.repairableRawPath)
}

public var hasUnrepairablePathCollisions: Bool {
    collisions.contains { $0.repairableRawPath == nil }
}
```

When merged collisions include an ambiguous versioned collision, set `repairableRawPath` to `nil` even if another value contains an orphan repair path.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter SVNWorkingCopySnapshotTests`

Expected: all snapshot tests pass.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit the snapshot classification**

```bash
git add Sources/SVNCore/SVNWorkingCopySnapshot.swift Tests/SVNCoreTests/SVNWorkingCopySnapshotTests.swift
git commit -m "정규화 동일 경로 제자리 복구 대상 분류"
```

### Task 2: Revalidate and Repair SVN Scheduling In Place

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNCore/Models.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Consumes: `SVNWorkingCopySnapshot.repairableAliasPaths` and `hasUnrepairablePathCollisions` from Task 1.
- Produces: `SVNClient.repairCanonicalAliases(at:credentials:) async throws -> SVNWorkingCopySnapshot` and `SVNError.pathAliasRepairFailed(paths:)`.

- [ ] **Step 1: Write failing command-log tests**

Create a fake SVN executable whose first verbose status contains an NFC managed path plus an exact NFD `missing revision=-1` alias and whose second status is clean. Assert that repair runs one revert with the exact NFD bytes, `--depth infinity`, and no `--remove-added`. Keep a real temporary file under the root and assert its `Data` is unchanged.

```swift
#expect(rawTargets.contains(Data(nfdRoot.utf8)))
#expect(log.contains("revert --depth infinity"))
#expect(!log.contains("--remove-added"))
#expect(try Data(contentsOf: localFile) == originalData)
```

Add a fake response with two versioned canonical aliases and assert no revert command is logged.

- [ ] **Step 2: Run repair tests and verify RED**

Run: `swift test --filter repairCanonicalAliases`

Expected: compilation fails because `repairCanonicalAliases` does not exist.

- [ ] **Step 3: Implement fresh-snapshot repair**

Fetch a fresh snapshot, reject if any collision is unrepairable, and pass the raw repair paths directly to `checkedRunWithTargets`. Do not use `normalizedCommitPaths`, because Swift `String` equality intentionally treats NFC/NFD as equal. Re-fetch and validate after revert.

```swift
public func repairCanonicalAliases(
    at path: String,
    credentials: SVNCredentials? = nil
) async throws -> SVNWorkingCopySnapshot {
    let before = try await workingCopySnapshot(at: path, credentials: credentials)
    guard !before.hasUnrepairablePathCollisions else {
        throw SVNError.pathNormalizationCollision(paths: before.collisions.map(\.displayPath))
    }
    let targets = before.repairableAliasPaths
    if !targets.isEmpty {
        _ = try checkedRunWithTargets(
            ["revert", "--depth", "infinity"],
            targets: targets,
            at: path,
            credentials: credentials
        )
    }
    let after = try await workingCopySnapshot(at: path, credentials: credentials)
    guard after.repairableAliasPaths.isEmpty else {
        throw SVNError.pathAliasRepairFailed(paths: after.collisions.map(\.displayPath))
    }
    return after
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter repairCanonicalAliases`

Expected: repair tests pass and command log has no `--remove-added`.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit the core repair operation**

```bash
git add Sources/SVNCore/SVNClient.swift Sources/SVNCore/Models.swift Tests/SVNCoreTests/SVNCredentialsTests.swift
git commit -m "정규화 동일 경로 SVN 예약 제자리 정리"
```

### Task 3: Repair Automatically Before Commit

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Test: `Tests/SVNCoreTests/SVNCredentialsTests.swift`

**Interfaces:**
- Consumes: the repair classification and exact-target revert from Tasks 1-2.
- Produces: commit preflight order `status -> revert -> status -> add/delete -> commit` with every commit target mapped to the unique repository path.

- [ ] **Step 1: Write a failing end-to-end commit command test**

Use a stateful fake SVN executable. The first status exposes an NFD scheduled alias plus a real modified file and a real unversioned file; revert switches the next status to a clean snapshot. Assert the exact command order and that add/commit targets use NFC repository ancestors.

```swift
#expect(commands == ["status", "revert", "status", "add", "commit"])
#expect(targets.contains(Data("00 사업관리/새 파일.hwp".utf8)))
#expect(!targets.contains(Data(nfdNewFile.utf8)))
```

- [ ] **Step 2: Run the commit test and verify RED**

Run: `swift test --filter commitRepairsCanonicalAliasesBeforeScheduling`

Expected: commit throws `pathNormalizationCollision` before revert.

- [ ] **Step 3: Integrate repair into commit preflight**

At the start of `commit`, fetch one snapshot. If it has repairable aliases and no unrepairable collision, run the exact-target revert and fetch a new snapshot. If an unrepairable collision remains, stop before add/delete. Continue using `resolvedPath(for:)`, `additionRollbackRoots`, and targeted scheduling rollback from the existing transaction-safe commit implementation.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter commit`

Expected: all commit tests pass, including Korean message, 20,000 targets, scheduling rollback, and alias repair.

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit commit-preflight integration**

```bash
git add Sources/SVNCore/SVNClient.swift Tests/SVNCoreTests/SVNCredentialsTests.swift
git commit -m "커밋 전 동일 한글 경로 자동 정리"
```

### Task 4: Replace Folder Picker with One-Click In-Place Repair

**Files:**
- Modify: `Sources/SVNMac/ProjectDependencies.swift`
- Modify: `Sources/SVNMac/DemoMode.swift`
- Modify: `Sources/SVNMac/ProjectStore+Recovery.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Modify: `Tests/SVNMacTests/ProjectStoreTests.swift`
- Modify: `Tests/SVNMacTests/ChangesViewPerformanceTests.swift`

**Interfaces:**
- Consumes: `SVNClient.repairCanonicalAliases(at:credentials:)`.
- Produces: `ProjectStore.repairCanonicalAliases() async`, a `동일 한글 경로 정리` action for repairable collisions, and the existing recovery sheet only for unrepairable collisions.

- [ ] **Step 1: Write failing store and UI source-contract tests**

Configure the stub client with a repairable collision. Invoke the store action and require that it calls in-place repair, refreshes statuses, and never sets `isShowingPathRecovery`. Require `ChangesView` to contain `동일 한글 경로 정리` and route repairable collisions to the new action.

```swift
await store.repairCanonicalAliases()
#expect(await client.repairRequestCount() == 1)
#expect(!store.isShowingPathRecovery)
#expect(store.pathCollisions.isEmpty)
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter ProjectStoreTests`

Expected: compilation fails because the protocol and store repair method do not exist.

- [ ] **Step 3: Implement protocol, store action, and conditional UI**

Add the client method to `SVNClientServing` and its demo/stub implementations. The store action uses the selected project's credentials, begins a `.recover(project.id)` operation, calls in-place repair, then refreshes. In `collisionRow`, call this action when `collision.repairableRawPath != nil`; otherwise retain `beginPathRecovery()`.

```swift
if collision.repairableRawPath != nil {
    Button(appLanguage.text("동일 한글 경로 정리", "Clean Up Equivalent Path")) {
        Task { await store.repairCanonicalAliases() }
    }
} else {
    Button(appLanguage.text("경로 자동 복구…", "Recover Paths…")) {
        Task { await store.beginPathRecovery() }
    }
}
```

- [ ] **Step 4: Run UI, store, and full tests**

Run: `swift test --filter ProjectStoreTests`

Run: `swift test --filter ChangesViewPerformanceTests`

Run: `swift test`

Expected: all tests pass and repairable collisions do not open a folder picker.

- [ ] **Step 5: Commit the one-click UI**

```bash
git add Sources/SVNMac/ProjectDependencies.swift Sources/SVNMac/DemoMode.swift Sources/SVNMac/ProjectStore+Recovery.swift Sources/SVNMac/ChangesView.swift Tests/SVNMacTests/ProjectStoreTests.swift Tests/SVNMacTests/ChangesViewPerformanceTests.swift
git commit -m "동일 한글 경로 원클릭 정리 추가"
```

### Task 5: Documentation and Final Verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: all earlier task behavior.
- Produces: user-facing explanation that local paths are not renamed and canonical aliases are repaired in place before commit.

- [ ] **Step 1: Update the user documentation**

Replace the statement that every normalization collision requires a new folder. Document that repairable NFC/NFD aliases are cleaned in place without renaming files, while truly ambiguous server paths remain blocked.

- [ ] **Step 2: Run final verification**

Run: `git diff --check`

Expected: no output.

Run: `swift test`

Expected: all tests pass with zero failures.

Run: `swift build -c release`

Expected: exit code 0.

- [ ] **Step 3: Commit documentation**

```bash
git add README.md
git commit -m "동일 한글 경로 정리 사용법 추가"
```

- [ ] **Step 4: Inspect final scope**

Run: `git status --short --branch`

Expected: clean `main` working tree with only committed implementation changes.
