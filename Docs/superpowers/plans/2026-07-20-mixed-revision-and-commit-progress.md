# Mixed Revision and Commit Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display the complete SVN working-copy revision range and show commit progress inside the button that started the operation.

**Architecture:** Parse the revision range from the existing bundled `svn status --verbose --xml` output into a small SVNCore value type. Keep remote freshness as the separate existing `workingCopyIsOutOfDate` result, place the timeline marker at the range maximum, and derive selected-project commit activity from `ProjectStore.activeOperations` for both the commit button and global toolbar spinner.

**Tech Stack:** Swift 6, SwiftUI for macOS, Foundation XMLParser, Swift Testing, Swift Package Manager

## Global Constraints

- Do not run `svn update` automatically after commit.
- Preserve the existing remote freshness algorithm and commit/authentication/error flows.
- Use the bundled `svn` executable; do not add a separately packaged `svnversion` binary.
- Keep `WorkspaceSplitView` as the changes/history outer container and do not introduce nested split views.
- Preserve all unrelated working-tree and staged changes.

---

### Task 1: Working-copy revision range model and XML parsing

**Files:**
- Modify: `Sources/SVNCore/Models.swift`
- Modify: `Sources/SVNCore/SVNXMLParser.swift`
- Modify: `Tests/SVNCoreTests/SVNXMLParserTests.swift`

**Interfaces:**
- Consumes: `SVNWorkingCopyEntry.revision: String?` parsed from `svn status --verbose --xml`.
- Produces: `SVNWorkingCopyRevision(minimum: String, maximum: String)`, `displayValue: String`, `timelineRevision: String`, and `SVNXMLParser.workingCopyRevision(from:) throws -> SVNWorkingCopyRevision`.

- [ ] **Step 1: Write failing parser and value tests**

```swift
@Test func parsesSingleWorkingCopyRevision() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="13295"/></entry>
      <entry path="README.md"><wc-status item="normal" revision="13295"/></entry>
    </target></status>
    """
    let revision = try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    #expect(revision.minimum == "13295")
    #expect(revision.maximum == "13295")
    #expect(revision.displayValue == "13295")
    #expect(revision.timelineRevision == "13295")
    #expect(!revision.isMixed)
}

@Test func parsesMixedWorkingCopyRevisionRange() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="13292"/></entry>
      <entry path="Sources/App.swift"><wc-status item="normal" revision="13295"/></entry>
      <entry path="draft.txt"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    let revision = try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    #expect(revision.minimum == "13292")
    #expect(revision.maximum == "13295")
    #expect(revision.displayValue == "13292–13295")
    #expect(revision.timelineRevision == "13295")
    #expect(revision.isMixed)
}

@Test func rejectsWorkingCopyRevisionWithoutVersionedEntries() {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="draft.txt"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    #expect(throws: SVNError.self) {
        try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter 'WorkingCopyRevision'`

Expected: compilation fails because `SVNXMLParser.workingCopyRevision`, `displayValue`, `timelineRevision`, and `isMixed` do not exist.

- [ ] **Step 3: Add the minimal range value and parser**

```swift
public struct SVNWorkingCopyRevision: Equatable, Sendable {
    public let minimum: String
    public let maximum: String

    public var isMixed: Bool { minimum != maximum }
    public var displayValue: String { isMixed ? "\(minimum)–\(maximum)" : maximum }
    public var timelineRevision: String { maximum }

    public init(minimum: String, maximum: String) {
        self.minimum = minimum
        self.maximum = maximum
    }
}
```

Add to `SVNXMLParser`:

```swift
public static func workingCopyRevision(from data: Data) throws -> SVNWorkingCopyRevision {
    let entries = try workingCopyEntries(from: data)
    let revisions = entries.compactMap(\.revision).compactMap(Int.init)
    guard let minimum = revisions.min(), let maximum = revisions.max() else {
        throw SVNError.malformedResponse
    }
    return SVNWorkingCopyRevision(minimum: String(minimum), maximum: String(maximum))
}
```

- [ ] **Step 4: Run focused parser tests and verify GREEN**

Run: `swift test --filter 'WorkingCopyRevision'`

Expected: all three range tests pass with zero failures.

- [ ] **Step 5: Commit the core range model**

```bash
git add Sources/SVNCore/Models.swift Sources/SVNCore/SVNXMLParser.swift Tests/SVNCoreTests/SVNXMLParserTests.swift
git commit -m "작업 복사본 혼합 리비전 범위 파싱 추가"
```

---

### Task 2: Load and expose the revision range

**Files:**
- Modify: `Sources/SVNCore/SVNClient.swift`
- Modify: `Sources/SVNMac/ProjectDependencies.swift`
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Modify: `Sources/SVNMac/DemoMode.swift`
- Modify: `Tests/SVNCoreTests/SVNCredentialsTests.swift`
- Modify: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: `SVNXMLParser.workingCopyRevision(from:)` from Task 1.
- Produces: `SVNClientServing.workingCopyRevision(at:credentials:) async throws -> SVNWorkingCopyRevision` and `ProjectStore.workingCopyRevision: SVNWorkingCopyRevision?`.

- [ ] **Step 1: Change focused tests to require a mixed range**

Replace the fake command response in `readsTrimmedWorkingCopyRevision` with:

```swift
case "$*" in
  *"status --verbose --xml"*) printf '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="37"/></entry><entry path="file.txt"><wc-status item="normal" revision="41"/></entry></target></status>' ;;
  *) exit 1 ;;
esac
```

Then assert:

```swift
#expect(revision == SVNWorkingCopyRevision(minimum: "37", maximum: "41"))
```

Update the refresh test stub to return `SVNWorkingCopyRevision(minimum: value, maximum: value)` and assert:

```swift
#expect(store.workingCopyRevision == SVNWorkingCopyRevision(minimum: "2", maximum: "2"))
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter 'readsTrimmedWorkingCopyRevision|staleRefreshDoesNotOverwriteNewlySelectedProject'`

Expected: compilation fails while the protocol/client/store still return `String`.

- [ ] **Step 3: Switch the client, protocol, store, demo, and stub to the range type**

In `SVNClient`:

```swift
public func workingCopyRevision(at path: String, credentials: SVNCredentials? = nil) async throws -> SVNWorkingCopyRevision {
    let result = try checkedRun(["status", "--verbose", "--xml"], at: path, credentials: credentials)
    return try SVNXMLParser.workingCopyRevision(from: Data(result.output.utf8))
}
```

Change every `SVNClientServing` implementation to return `SVNWorkingCopyRevision`. Store the returned range unchanged in `ProjectStore.refresh()`. In `DemoSVNClient`, return `SVNWorkingCopyRevision(minimum: "1842", maximum: "1842")`. In the test stub, wrap its existing per-path string in a single-value range.

- [ ] **Step 4: Run focused client and store tests and verify GREEN**

Run: `swift test --filter 'readsTrimmedWorkingCopyRevision|staleRefreshDoesNotOverwriteNewlySelectedProject'`

Expected: both tests pass with zero failures.

- [ ] **Step 5: Commit range loading**

```bash
git add Sources/SVNCore/SVNClient.swift Sources/SVNMac/ProjectDependencies.swift Sources/SVNMac/ProjectStore.swift Sources/SVNMac/DemoMode.swift Tests/SVNCoreTests/SVNCredentialsTests.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "새로고침에서 작업 복사본 리비전 범위 사용"
```

---

### Task 3: Present mixed revisions accurately in history

**Files:**
- Modify: `Sources/SVNMac/HistoryView.swift`
- Test: `Tests/SVNCoreTests/SVNXMLParserTests.swift`

**Interfaces:**
- Consumes: `ProjectStore.workingCopyRevision: SVNWorkingCopyRevision?` from Task 2 and existing `SVNHistoryTimeline(logs:workingCopyRevision:)`.
- Produces: Header text `r13292–13295`, a `혼합 리비전` / `Mixed revisions` badge, and a timeline marker at `maximum`.

- [ ] **Step 1: Extend the timeline regression test with the mixed range maximum**

```swift
let mixed = SVNWorkingCopyRevision(minimum: "47", maximum: "50")
let mixedTimeline = SVNHistoryTimeline(logs: logs, workingCopyRevision: mixed.timelineRevision)
#expect(mixedTimeline.graphEntryRevision == "50")
```

- [ ] **Step 2: Run the focused timeline test and verify GREEN baseline**

Run: `swift test --filter placesWorkingCopyRevisionInHistoryTimeline`

Expected: the test passes, proving the existing timeline accepts the range maximum without changing its algorithm.

- [ ] **Step 3: Pass the maximum to the timeline and use the display range in the summary**

Use these values in `HistoryView`:

```swift
let timeline = SVNHistoryTimeline(
    logs: store.logs,
    workingCopyRevision: store.workingCopyRevision?.timelineRevision
)
```

```swift
if let revision = store.workingCopyRevision {
    Label(
        appLanguage.text(
            "내 로컬 폴더 r\(revision.displayValue)",
            "My local folder r\(revision.displayValue)"
        ),
        systemImage: "macbook"
    )
    if revision.isMixed {
        historyBadge(appLanguage.text("혼합 리비전", "Mixed revisions"), color: .gray)
    }
}
```

For marker insertion and rows, pass `revision.timelineRevision`. Change the exact-range badge and help copy to say `내 로컬 최고` / `My local maximum` when `isMixed` is true; keep `내 로컬 기준` / `My local base` for a single revision.

- [ ] **Step 4: Build the app target**

Run: `swift build`

Expected: build completes with exit code 0 and no type mismatch involving `SVNWorkingCopyRevision`.

- [ ] **Step 5: Commit history presentation**

```bash
git add Sources/SVNMac/HistoryView.swift Tests/SVNCoreTests/SVNXMLParserTests.swift
git commit -m "커밋 기록에 혼합 리비전 범위 표시"
```

---

### Task 4: Put commit progress on the commit button

**Files:**
- Modify: `Sources/SVNMac/ProjectStore.swift`
- Modify: `Sources/SVNMac/ChangesView.swift`
- Modify: `Sources/SVNMac/ContentView.swift`
- Modify: `Tests/SVNMacTests/ProjectStoreTests.swift`

**Interfaces:**
- Consumes: `ProjectStore.activeOperations: [ProjectOperation]` and `ProjectOperation.Kind.commit(SVNProject.ID)`.
- Produces: `isCommittingSelectedProject: Bool` and `showsGlobalProgress: Bool`.

- [ ] **Step 1: Write failing operation-state tests**

```swift
@MainActor
@Test func commitProgressTracksOnlySelectedProjectsCommit() {
    let selected = SVNProject(name: "선택", path: "/tmp/selected")
    let other = SVNProject(name: "다른", path: "/tmp/other")
    let store = makeStore(projects: [selected, other])

    #expect(!store.isCommittingSelectedProject)
    #expect(!store.showsGlobalProgress)

    let refreshID = store.beginOperation(.refresh(selected.id))
    #expect(!store.isCommittingSelectedProject)
    #expect(store.showsGlobalProgress)
    store.endOperation(refreshID)

    let otherCommitID = store.beginOperation(.commit(other.id))
    #expect(!store.isCommittingSelectedProject)
    #expect(store.showsGlobalProgress)
    store.endOperation(otherCommitID)

    let commitID = store.beginOperation(.commit(selected.id))
    #expect(store.isCommittingSelectedProject)
    #expect(!store.showsGlobalProgress)
    store.endOperation(commitID)
}
```

- [ ] **Step 2: Run the operation-state test and verify RED**

Run: `swift test --filter commitProgressTracksOnlySelectedProjectsCommit`

Expected: compilation fails because both computed properties are missing.

- [ ] **Step 3: Implement selected-project operation state**

```swift
var isCommittingSelectedProject: Bool {
    guard let projectID = selectedProjectID else { return false }
    return activeOperations.contains { $0.kind == .commit(projectID) }
}

var showsGlobalProgress: Bool {
    isWorking && !isCommittingSelectedProject
}
```

- [ ] **Step 4: Run the operation-state test and verify GREEN**

Run: `swift test --filter commitProgressTracksOnlySelectedProjectsCommit`

Expected: the test passes with zero failures.

- [ ] **Step 5: Change the commit button label and toolbar spinner**

In `ChangesView`, replace the string-only button with:

```swift
Button(action: submitCommitAfterEndingTextInput) {
    HStack(spacing: 6) {
        if store.isCommittingSelectedProject {
            ProgressView().controlSize(.small)
        }
        Text(store.isCommittingSelectedProject
            ? appLanguage.text("커밋 중…", "Committing…")
            : appLanguage.text("선택 항목 커밋", "Commit Selected"))
    }
}
.buttonStyle(.borderedProminent)
.disabled(store.selectedPaths.isEmpty
    || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    || store.isWorking)
```

In `ContentView`, replace the unconditional busy spinner with a stable-size non-commit spinner:

```swift
if store.showsGlobalProgress {
    ProgressView()
        .controlSize(.small)
        .frame(width: 16, height: 16)
}
```

- [ ] **Step 6: Build the app target**

Run: `swift build`

Expected: build completes with exit code 0.

- [ ] **Step 7: Commit progress presentation**

```bash
git add Sources/SVNMac/ProjectStore.swift Sources/SVNMac/ChangesView.swift Sources/SVNMac/ContentView.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "선택 커밋 버튼에 진행 상태 표시"
```

---

### Task 5: Full verification and delivery

**Files:**
- Verify: `Docs/LayoutArchitecture.md`
- Verify: all files modified by Tasks 1–4

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: a tested, scoped commit series with no unrelated files staged.

- [ ] **Step 1: Run the entire test suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 2: Check patch integrity and scope**

Run: `git diff --check`

Expected: no whitespace errors.

Run: `git status --short`

Expected: only pre-existing unrelated changes remain; this feature's files are committed.

- [ ] **Step 3: Verify layout invariants from the architecture document**

Confirm the changes retain `WorkspaceSplitView`, add no nested `HSplitView`/`VSplitView`, keep the prominent button style, and introduce no major window/sidebar/panel size constants outside `AppLayout.swift`.

- [ ] **Step 4: Report the exact commit hashes and retained unrelated changes**

Run: `git log --oneline --decorate -8`

Expected: the design, core range, refresh integration, history presentation, and commit-progress commits are visible; existing history-loading work remains separate.
