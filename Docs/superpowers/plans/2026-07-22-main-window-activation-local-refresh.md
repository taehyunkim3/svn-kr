# Main Window Activation Local Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the selected working copy's local changes and file browser once whenever the SVN Mac main window becomes key, without requesting remote history.

**Architecture:** Split the local snapshot portion of `ProjectStore.refresh()` into a reusable local-only operation while preserving the full manual refresh path. Add a main-window-specific AppKit observer hosted by SwiftUI and route its activation callback to the local-only store and file-browser refreshes.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, Swift Package Manager

## Global Constraints

- Support macOS 14 and later.
- Observe only the main window that hosts `ContentView`.
- Refresh local working-copy status and the file list once per main-window activation.
- Do not request remote logs or out-of-date state during automatic activation refresh.
- Keep the toolbar refresh and project-selection refresh as full refreshes.
- Skip automatic refresh in demo mode, without a selected project, or while another operation is active.
- Preserve request-ID checks so stale results cannot overwrite a newly selected project.

---

### Task 1: Extract a local-only working-copy refresh

**Files:**
- Modify: `Sources/SVNMac/ProjectDependencies.swift:170-190`
- Modify: `Sources/SVNMac/ProjectStore.swift:145-170,371-430`
- Modify: `Tests/SVNMacTests/ProjectStoreTests.swift:850-900,1260-1430`

**Interfaces:**
- Consumes: `SVNClientServing.workingCopySnapshot`, `SVNClientServing.workingCopyRepositoryPath`, and existing `ProjectStore.canApplyRefresh` request validation.
- Produces: `ProjectStore.refreshLocalWorkingCopy() async` and `ProjectOperation.Kind.refreshLocal(SVNProject.ID)`.

- [ ] **Step 1: Write failing store tests for local-only and full refresh behavior**

Add remote request counters to `StubSVNClient` and tests equivalent to:

```swift
@MainActor
@Test func localWorkingCopyRefreshUpdatesStatusWithoutRemoteHistoryRequests() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/local-refresh")
    let entry = SVNStatusEntry(path: "보고서.xlsx", item: .modified, revision: "12")
    let client = StubSVNClient(
        snapshotsByPath: [
            project.path: SVNWorkingCopySnapshot(
                statuses: [entry],
                revision: SVNWorkingCopyRevision(minimum: "12", maximum: "12"),
                collisions: [],
                versionedPathsByCanonicalKey: [entry.path: [entry.path]]
            ),
        ]
    )
    let store = makeStore(projects: [project], client: client)

    await store.refreshLocalWorkingCopy()

    #expect(store.statuses == [entry])
    #expect(store.workingCopyRevision == SVNWorkingCopyRevision(minimum: "12", maximum: "12"))
    #expect(await client.remoteRefreshRequestCounts() == RemoteRefreshRequestCounts(log: 0, outOfDate: 0))
}

@MainActor
@Test func fullRefreshStillRequestsRemoteHistoryAndOutOfDateState() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/full-refresh")
    let client = StubSVNClient(revisionsByPath: [project.path: "12"])
    let store = makeStore(projects: [project], client: client)

    await store.refresh()

    #expect(await client.remoteRefreshRequestCounts() == RemoteRefreshRequestCounts(log: 1, outOfDate: 1))
}
```

Extend the history-loading test so `.refreshLocal(selectedProject.id)` does not set `isHistoryLoading`.

- [ ] **Step 2: Run the focused tests and verify the new API is missing**

Run:

```bash
swift test --filter 'localWorkingCopyRefresh|fullRefreshStillRequests|historyLoadingTracks'
```

Expected: compilation fails because `refreshLocalWorkingCopy`, `refreshLocal`, and the counter helper are not defined.

- [ ] **Step 3: Add the local operation kind and extract the shared local refresh**

Add the new operation kind:

```swift
case refreshLocal(SVNProject.ID)
```

Refactor `ProjectStore` to expose a local-only entry point and share snapshot application with the full refresh:

```swift
func refreshLocalWorkingCopy() async {
    guard let project = selectedProject else { return }
    let requestID = prepareRefreshRequest()
    let operationID = beginOperation(.refreshLocal(project.id))
    defer { endOperation(operationID) }
    _ = await applyLocalWorkingCopyRefresh(for: project, requestID: requestID)
}

func refresh() async {
    guard let project = selectedProject else { return }
    let requestID = prepareRefreshRequest()
    let operationID = beginOperation(.refresh(project.id))
    defer { endOperation(operationID) }

    guard await applyLocalWorkingCopyRefresh(for: project, requestID: requestID) else { return }
    do {
        let projectCredentials = try credentials(for: project)
        async let newLogs = client.log(
            at: project.path,
            limit: 50,
            endingAtRevision: nil,
            credentials: projectCredentials,
            allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
        )
        async let outOfDate = client.workingCopyIsOutOfDate(
            at: project.path,
            credentials: projectCredentials,
            allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
        )
        let (logs, isWorkingCopyOutOfDate) = try await (newLogs, outOfDate)
        guard canApplyRefresh(requestID, projectID: project.id) else { return }
        self.logs = logs
        hasMoreHistory = logs.count == 50
        self.isWorkingCopyOutOfDate = isWorkingCopyOutOfDate
        updateRemoteSummary(for: project.id, needsUpdate: isWorkingCopyOutOfDate)
        notice = AppLanguage.current.text(
            "\(project.name) 새로고침 완료",
            "\(project.name) refreshed"
        )
    } catch {
        if canApplyRefresh(requestID, projectID: project.id) {
            handleRemoteError(error, project: project, action: .refreshHistory)
        }
    }
}

private func prepareRefreshRequest() -> UUID {
    let requestID = UUID()
    refreshRequestID = requestID
    isWorkingCopyOutOfDate = nil
    isShowingPathRecovery = false
    pathRecoveryPreview = nil
    pathRecoverySourceProjectID = nil
    return requestID
}

private func applyLocalWorkingCopyRefresh(
    for project: SVNProject,
    requestID: UUID
) async -> Bool {
    do {
        async let newSnapshot = client.workingCopySnapshot(at: project.path, credentials: nil)
        async let newRepositoryPath = client.workingCopyRepositoryPath(at: project.path, credentials: nil)
        let (snapshot, repositoryPath) = try await (newSnapshot, newRepositoryPath)
        guard canApplyRefresh(requestID, projectID: project.id) else { return false }
        statuses = snapshot.statuses
        workingCopyRevision = snapshot.revision
        pathCollisions = snapshot.collisions
        workingCopyRepositoryPath = repositoryPath
        selectedPaths.formIntersection(selectableStatusPaths)
        updateLocalSummary(for: project.id, statuses: snapshot.statuses)
        notice = AppLanguage.current.text(
            "\(project.name) 로컬 변경 사항 확인 완료",
            "\(project.name) local changes refreshed"
        )
        return true
    } catch {
        if canApplyRefresh(requestID, projectID: project.id) {
            errorMessage = localizedError(error)
        }
        return false
    }
}
```

Add the value type and actor-isolated counters below, then increment the counters inside `log` and `workingCopyIsOutOfDate` so the tests observe actual calls:

```swift
private struct RemoteRefreshRequestCounts: Equatable, Sendable {
    let log: Int
    let outOfDate: Int
}

private actor StubSVNClient: SVNClientServing {
    private var logRequests = 0
    private var outOfDateRequests = 0

    func remoteRefreshRequestCounts() -> RemoteRefreshRequestCounts {
        RemoteRefreshRequestCounts(log: logRequests, outOfDate: outOfDateRequests)
    }

    func log(
        at path: String,
        limit: Int,
        endingAtRevision: String?,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool
    ) async throws -> [SVNLogEntry] {
        logRequests += 1
        await delay(for: path)
        return [makeLog(revision: revisionsByPath[path] ?? "0")]
    }

    func workingCopyIsOutOfDate(
        at path: String,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool
    ) async throws -> Bool {
        outOfDateRequests += 1
        await delay(for: path)
        return false
    }
}
```

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
swift test --filter 'localWorkingCopyRefresh|fullRefreshStillRequests|historyLoadingTracks'
```

Expected: all matching tests pass.

- [ ] **Step 5: Commit the local refresh extraction**

```bash
git add Sources/SVNMac/ProjectDependencies.swift Sources/SVNMac/ProjectStore.swift Tests/SVNMacTests/ProjectStoreTests.swift
git commit -m "refactor: 로컬 작업 복사본 갱신 분리"
```

---

### Task 2: Observe main-window activation and trigger local refresh

**Files:**
- Create: `Sources/SVNMac/MainWindowActivationView.swift`
- Modify: `Sources/SVNMac/ContentView.swift:1-110,170-180`
- Create: `Tests/SVNMacTests/MainWindowActivationTests.swift`

**Interfaces:**
- Consumes: `ProjectStore.refreshLocalWorkingCopy() async` from Task 1 and the local-only `ProjectStore.loadWorkingCopyFiles() async`.
- Produces: `MainWindowActivationView(onActivation:)`, hosted by `ContentView`, and `MainWindowActivationMonitor.observe(_:)` for the AppKit window lifecycle.

- [ ] **Step 1: Write failing tests for window-specific observation and ContentView wiring**

Create tests equivalent to:

```swift
import AppKit
import Foundation
import Testing
@testable import SVNMac

@MainActor
@Test func activationMonitorObservesOneWindowOnceAndMovesToReplacementWindow() {
    let first = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    let second = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    var activationCount = 0
    let monitor = MainWindowActivationMonitor { activationCount += 1 }

    monitor.observe(first)
    monitor.observe(first)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    #expect(activationCount == 1)

    monitor.observe(second)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second)
    #expect(activationCount == 2)
}

@Test func contentViewUsesMainWindowActivationForLocalOnlyRefresh() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac/ContentView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("MainWindowActivationView"))
    #expect(source.contains("refreshSelectedProjectLocally"))
    #expect(source.contains("store.refreshLocalWorkingCopy()"))
    #expect(source.contains("store.loadWorkingCopyFiles()"))
    #expect(!source.contains("@Environment(\\.scenePhase)"))
}
```

- [ ] **Step 2: Run the focused tests and verify the observer is missing**

Run:

```bash
swift test --filter 'activationMonitor|contentViewUsesMainWindowActivation'
```

Expected: compilation fails because `MainWindowActivationMonitor` does not exist.

- [ ] **Step 3: Implement the AppKit window observer**

Create `MainWindowActivationView.swift` with these responsibilities:

```swift
import AppKit
import SwiftUI

@MainActor
final class MainWindowActivationMonitor: NSObject {
    private weak var observedWindow: NSWindow?
    private let onActivation: () -> Void

    init(onActivation: @escaping () -> Void) {
        self.onActivation = onActivation
    }

    func observe(_ window: NSWindow?) {
        guard observedWindow !== window else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: observedWindow
        )
        observedWindow = window
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        if window.isKeyWindow { onActivation() }
    }

    @objc private func windowDidBecomeKey() {
        onActivation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private final class WindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

struct MainWindowActivationView: NSViewRepresentable {
    let onActivation: () -> Void

    func makeCoordinator() -> MainWindowActivationMonitor {
        MainWindowActivationMonitor(onActivation: onActivation)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        view.onWindowChange = context.coordinator.observe
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.observe(nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: MainWindowActivationMonitor) {
        coordinator.observe(nil)
    }
}
```

If Swift 6 actor diagnostics require isolation annotations, keep every AppKit lifecycle type and callback on `@MainActor`; do not weaken concurrency checking.

- [ ] **Step 4: Wire activation to local-only refresh**

Remove the `scenePhase` environment and its `.onChange`. Add a zero-size background observer to `ContentView`:

```swift
.background {
    MainWindowActivationView {
        guard store.selectedProject != nil, !store.isWorking else { return }
        Task { await refreshSelectedProjectLocally() }
    }
    .frame(width: 0, height: 0)
}
```

Add the local helper. Keep the existing `refreshSelectedProject()` method as written below for the toolbar and project selection:

```swift
private func refreshSelectedProject() async {
    guard !store.isDemoMode else { return }
    async let project: Void = store.refresh()
    async let files: Void = store.refreshWorkingCopyBrowser()
    _ = await (project, files)
}

private func refreshSelectedProjectLocally() async {
    guard !store.isDemoMode else { return }
    async let changes: Void = store.refreshLocalWorkingCopy()
    async let files: Void = store.loadWorkingCopyFiles()
    _ = await (changes, files)
}
```

- [ ] **Step 5: Run focused tests and the complete suite**

Run:

```bash
swift test --filter 'activationMonitor|contentViewUsesMainWindowActivation'
swift test
```

Expected: the focused tests pass, followed by the complete suite with zero failures and no compiler warnings.

- [ ] **Step 6: Commit the activation behavior**

```bash
git add Sources/SVNMac/MainWindowActivationView.swift Sources/SVNMac/ContentView.swift Tests/SVNMacTests/MainWindowActivationTests.swift
git commit -m "feat: 메인 창 활성화 시 로컬 변경 자동 갱신"
```

---

### Task 3: Final scope and regression verification

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: all outputs from Tasks 1 and 2.
- Produces: verification evidence that the isolated branch is ready for integration.

- [ ] **Step 1: Check formatting, scope, and repository state**

Run:

```bash
git diff --check master...HEAD
git status --short --branch
git diff --stat master...HEAD
```

Expected: no whitespace errors, a clean worktree, and changes limited to the design/plan, local refresh extraction, window observer, ContentView wiring, and their tests.

- [ ] **Step 2: Run the final full test suite**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.
