# Large Selected Commit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a selected commit with tens of thousands of SVN paths remain responsive, avoid redundant subprocesses, and produce one SVN revision.

**Architecture:** Replace repeated array scans with set/dictionary lookups, normalize selected paths at directory boundaries, and pass batches through UTF-8 SVN `--targets` files. Keep the public commit interface and existing authentication/error flow unchanged.

**Tech Stack:** Swift 6, Foundation `Process` and `FileManager`, SVN CLI, Swift Testing, Swift Package Manager

## Global Constraints

- One selected commit must produce exactly one SVN revision.
- Preserve selected-path semantics, credentials, UTF-8 locale, certificate handling, and existing error propagation.
- Do not introduce a command-line argument-length dependency.
- Preserve unrelated working-tree and staged changes.
- No layout files or SwiftUI sizing constants are changed.

---

### Task 1: Linear conflict validation

**Files:**
- Modify: `Sources/SVNMac/ProjectStore.swift:401-407`
- Test: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: `ProjectStore.statuses: [SVNStatusEntry]` and `selectedPaths: Set<String>`.
- Produces: internal `ProjectStore.containsSelectedConflict(selectedPaths:statuses:) -> Bool` and the same `commit(message:) async -> Bool` behavior.

- [ ] **Step 1: Write the failing regression test**

Call the new conflict-checking unit with 20,000 modified entries plus one conflicted entry. Assert that a modified-only selection is allowed and a selection containing the conflict is rejected.

```swift
@Test @MainActor func checksConflictsInLargeSelection() {
    let statuses = (0..<20_000).map {
        SVNStatusEntry(path: "Sources/file-\($0).swift", item: .modified)
    } + [SVNStatusEntry(path: "Sources/conflict.swift", item: .conflicted)]
    let allowed = Set(statuses.dropLast().map(\.path))

    #expect(!ProjectStore.containsSelectedConflict(selectedPaths: allowed, statuses: statuses))
    #expect(ProjectStore.containsSelectedConflict(
        selectedPaths: ["Sources/conflict.swift"],
        statuses: statuses
    ))
}
```

- [ ] **Step 2: Run the focused test and establish the RED performance baseline**

Run: `swift test --filter checksConflictsInLargeSelection`

Expected: compilation fails because `ProjectStore.containsSelectedConflict` does not exist.

- [ ] **Step 3: Replace the repeated scan with set intersection**

```swift
static func containsSelectedConflict(
    selectedPaths: Set<String>,
    statuses: [SVNStatusEntry]
) -> Bool {
    let conflictedPaths = Set(statuses.lazy.filter { $0.item == .conflicted }.map(\.path))
    return !selectedPaths.isDisjoint(with: conflictedPaths)
}

guard !Self.containsSelectedConflict(selectedPaths: selectedPaths, statuses: statuses) else {
    errorMessage = AppLanguage.current.text(
        "충돌 파일은 해결 완료 처리 후 커밋할 수 있습니다.",
        "Resolve conflicted files before committing."
    )
    return false
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `swift test --filter checksConflictsInLargeSelection`

Expected: PASS with one allowed commit and one blocked commit.

- [ ] **Step 5: Commit the linear validation change**

```bash
git add Sources/SVNMac/ProjectStore.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "대량 선택 충돌 검사를 선형화"
```

---

### Task 2: Normalize paths and batch SVN targets

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift:319-342`
- Modify: `Tests/SVNCoreTests/SVNCredentialsTests.swift:272-308`

**Interfaces:**
- Consumes: `SVNClient.commit(at:paths:message:credentials:allowUntrustedServerCertificate:)`.
- Produces: internal `normalizedCommitPaths(_:) -> [String]` and `withTargetsFile(paths:_:) throws -> SVNCommandResult`; public API remains unchanged.

- [ ] **Step 1: Write failing target batching tests**

Create a fake SVN executable that logs the command name, argument count, and contents of the file following `--targets`. Its status response contains a missing directory and descendants, an unversioned directory, and a similarly prefixed modified sibling.

```swift
let paths = [
    "Old", "Old/file.txt", "Old/nested/file.txt",
    "New", "Application/file.swift", "App/file.swift"
]
let result = try await client.commit(at: directory.path, paths: paths, message: "batch")

#expect(result.contains("commit-count=1"))
#expect(log.contains("delete-targets=Old"))
#expect(!log.contains("Old/file.txt"))
#expect(log.contains("add-targets=New"))
#expect(log.contains("Application/file.swift"))
#expect(log.contains("App/file.swift"))
```

Add a second test with 20,000 long paths and assert the fake executable reaches one `commit` invocation and reads all targets from a file. This test must not interpolate all paths into `$*`.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter 'batchesSelectedCommitTargets|commitsTwentyThousandPathsThroughTargetsFile'`

Expected: FAIL because commit still passes paths after `--`, invokes add/delete per item, and does not normalize descendants.

- [ ] **Step 3: Add path normalization**

Add an internal helper that sorts paths by component count and lexical order and retains a path only when no retained path is its directory-boundary ancestor.

```swift
static func normalizedCommitPaths(_ paths: [String]) -> [String] {
    let ordered = Set(paths).sorted {
        let leftDepth = $0.split(separator: "/").count
        let rightDepth = $1.split(separator: "/").count
        return leftDepth == rightDepth ? $0 < $1 : leftDepth < rightDepth
    }
    var retained: [String] = []
    for path in ordered where !retained.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
        retained.append(path)
    }
    return retained
}
```

- [ ] **Step 4: Add scoped UTF-8 targets files and batch commands**

Create each targets file inside the existing command temporary-directory lifecycle. Write one relative path plus newline per item using atomic UTF-8 data writes. Pass `--targets`, the file path, and no expanded path list to `checkedRun`.

```swift
let statusByPath = Dictionary(uniqueKeysWithValues: currentStatuses.map { ($0.path, $0.item) })
let normalizedPaths = Self.normalizedCommitPaths(paths)
let additions = Self.normalizedCommitPaths(paths.filter { statusByPath[$0] == .unversioned })
let deletions = Self.normalizedCommitPaths(paths.filter { statusByPath[$0] == .missing })

if !additions.isEmpty {
    _ = try checkedRunWithTargets(["add", "--parents"], targets: additions, at: path, credentials: credentials)
}
if !deletions.isEmpty {
    _ = try checkedRunWithTargets(["delete", "--force"], targets: deletions, at: path, credentials: credentials)
}
return try checkedRunWithTargets(
    ["commit", "--message", message],
    targets: normalizedPaths,
    at: path,
    credentials: credentials,
    allowUntrustedServerCertificate: allowUntrustedServerCertificate
).output
```

The helper appends the SVN `--targets` option to the subcommand arguments:

```swift
try checkedRun(
    arguments + ["--targets", targetsURL.path],
    at: path,
    credentials: credentials,
    allowUntrustedServerCertificate: allowUntrustedServerCertificate
)
```

- [ ] **Step 5: Update the existing Korean-message assertion**

Read the targets file inside the fake executable and keep these assertions:

```swift
#expect(result.contains("LANG=en_US.UTF-8"))
#expect(result.contains("LC_ALL=en_US.UTF-8"))
#expect(result.contains("message=한글 커밋 메시지"))
#expect(result.contains("target=한글.txt"))
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run: `swift test --filter 'batchesSelectedCommitTargets|commitsTwentyThousandPathsThroughTargetsFile|commitsKoreanMessageWithUTF8Locale'`

Expected: all focused tests pass; the fake SVN log shows at most one add, one delete, and exactly one commit.

- [ ] **Step 7: Run full verification**

Run: `swift test`

Expected: all SVNCoreTests and SVNMacTests pass with zero failures.

Run: `swift build`

Expected: the SVNMac executable builds successfully.

- [ ] **Step 8: Commit the batching implementation**

```bash
git add Sources/SVNCore/SVNClient.swift Tests/SVNCoreTests/SVNCredentialsTests.swift
git commit -m "대량 선택 커밋을 대상 파일로 일괄 처리"
```
