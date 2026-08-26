import Darwin
import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func revisionSaveExportsHistoricalBinaryBytesOutsideWorkingCopy() async throws {
    let fixture = try RevisionSVNFixture()
    defer { fixture.remove() }
    let original = Data([0x00, 0x50, 0x4B, 0x03, 0x04, 0xFF, 0x0A, 0x80])
    let changed = Data([0x48, 0x57, 0x50, 0x00, 0xFE])
    try fixture.write(original, relativePath: "document.xlsx")
    try fixture.addAndCommit(message: "original")
    try fixture.write(changed, relativePath: "document.xlsx")
    try fixture.commit(message: "changed")
    let destination = fixture.externalDestination.appendingPathComponent("saved-as.xlsx")

    try await RevisionFileService().saveRevision(
        using: fixture.client,
        workingCopyPath: fixture.workingCopy.path,
        relativePath: "document.xlsx",
        revision: "2",
        destinationURL: destination,
        credentials: nil,
        allowUntrustedServerCertificate: false,
        allowedServerCertificateFailures: []
    )

    #expect(try Data(contentsOf: destination) == original)
    #expect(try Data(contentsOf: fixture.workingCopy.appendingPathComponent("document.xlsx")) == changed)
}

@Test func realSVNRevisionRestorePreservesCurrentBinaryAndLeavesHistoricalBytesModified() async throws {
    let fixture = try RevisionSVNFixture()
    defer { fixture.remove() }
    let original = Data([0x00, 0x50, 0x4B, 0x03, 0x04, 0xFF, 0x0A, 0x80])
    let current = Data([0x48, 0x57, 0x50, 0x00, 0xFE])
    try fixture.write(original, relativePath: "document.xlsx")
    try fixture.addAndCommit(message: "original")
    try fixture.write(current, relativePath: "document.xlsx")
    try fixture.commit(message: "changed")
    let backupRoot = fixture.root.appendingPathComponent("revision-backups", isDirectory: true)
    let historical = try await fixture.client.fileContents(
        at: fixture.workingCopy.path,
        relativePath: "document.xlsx",
        revision: "2"
    )
    let result = try await RevisionFileService(backupRootURL: backupRoot).restoreWorkingFile(
        contents: historical,
        workingCopyPath: fixture.workingCopy.path,
        relativePath: "document.xlsx",
        projectID: UUID(),
        revision: "2"
    )

    let workingFile = fixture.workingCopy.appendingPathComponent("document.xlsx")
    #expect(try Data(contentsOf: workingFile) == original)
    #expect(try fixture.status().contains("M       document.xlsx"))
    #expect(try Data(contentsOf: #require(result.recoveryURL)) == current)
}

@Test func realSVNRevisionRestoreBringsBackLocallyDeletedVersionedFile() async throws {
    let fixture = try RevisionSVNFixture()
    defer { fixture.remove() }
    let original = Data([0x50, 0x4B, 0x03, 0x04, 0xFF, 0x0A])
    let current = Data([0x48, 0x57, 0x50, 0x00, 0xFE])
    try fixture.write(original, relativePath: "forms/report.xlsx")
    try fixture.addAndCommit(message: "original")
    try fixture.write(current, relativePath: "forms/report.xlsx")
    try fixture.commit(message: "changed")
    let workingFile = fixture.workingCopy.appendingPathComponent("forms/report.xlsx")
    // 파인더에서 파일을 지운 상태입니다. `svn status`가 `!`로 보고합니다.
    try FileManager.default.removeItem(at: workingFile)
    #expect(try fixture.status().contains("!       forms/report.xlsx"))
    let backupRoot = fixture.root.appendingPathComponent("revision-backups", isDirectory: true)
    let historical = try await fixture.client.fileContents(
        at: fixture.workingCopy.path,
        relativePath: "forms/report.xlsx",
        revision: "2"
    )

    let result = try await RevisionFileService(backupRootURL: backupRoot).restoreWorkingFile(
        contents: historical,
        workingCopyPath: fixture.workingCopy.path,
        relativePath: "forms/report.xlsx",
        projectID: UUID(),
        revision: "2"
    )

    #expect(result.recoveryURL == nil)
    #expect(try Data(contentsOf: workingFile) == original)
    #expect(try fixture.status().contains("M       forms/report.xlsx"))
}

@Test func revisionRestorePreservesRecoveryCopyAndAtomicallyReplacesWorkingFile() async throws {
    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-restore-service-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }
    let workingCopy = fixtureRoot.appendingPathComponent("working-copy", isDirectory: true)
    let backupRoot = fixtureRoot.appendingPathComponent("backups", isDirectory: true)
    let workingFile = workingCopy.appendingPathComponent("forms/report.hwp")
    let current = Data([0x48, 0x57, 0x50, 0x00, 0x01, 0xFF])
    let historical = Data([0x48, 0x57, 0x50, 0x00, 0x02, 0x80])
    try FileManager.default.createDirectory(
        at: workingFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try current.write(to: workingFile)
    let replacementObservation = ReplacementObservation()
    let service = RevisionFileService(
        backupRootURL: backupRoot,
        replaceItem: { destination, stagedFile in
            replacementObservation.record(
                try Data(contentsOf: destination) == current
            )
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: stagedFile,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        }
    )

    let result = try await service.restoreWorkingFile(
        contents: historical,
        workingCopyPath: workingCopy.path,
        relativePath: "forms/report.hwp",
        projectID: UUID(),
        revision: "17"
    )

    #expect(replacementObservation.observedOriginalDestination)
    #expect(try Data(contentsOf: #require(result.recoveryURL)) == current)
    #expect(try Data(contentsOf: workingFile) == historical)
    let siblings = try FileManager.default.contentsOfDirectory(
        at: workingFile.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    )
    #expect(!siblings.contains { $0.lastPathComponent.hasPrefix(".svn-mac-revision-restore-") })
}

@MainActor
@Test func revisionRestoreRequiresExplicitDestructiveConfirmation() throws {
    let project = SVNProject(name: "first", path: "/tmp/revision-confirmation")
    let store = revisionRestoreStore(projects: [project])
    let fileHistoryRequest = FileHistoryRequest(
        projectID: project.id,
        relativePath: "forms/report.xlsx"
    )
    store.fileHistoryRequest = fileHistoryRequest

    store.requestHistoryRevisionRestore(revision: "31")

    let request = try #require(store.recoveryState.historyRevisionRestoreRequest)
    #expect(request.fileHistoryRequestID == fileHistoryRequest.id)
    #expect(request.projectID == project.id)
    #expect(request.revision == "31")
    #expect(request.relativePath == "forms/report.xlsx")
    #expect(store.recoveryState.historyRevisionOperation == nil)
}

@MainActor
@Test func historyRevisionActionsPreserveRepositoryPathUTF8Bytes() throws {
    let project = SVNProject(name: "project", path: "/tmp/revision-history-path")
    let store = revisionRestoreStore(projects: [project])
    let repositoryFilePath = "/trunk/문서/주간보고서.hwp".decomposedStringWithCanonicalMapping
    store.workingCopyRepositoryPath = "/trunk"

    store.prepareHistoryRevisionActions(
        revision: "7",
        changedPath: SVNChangedPath(
            path: repositoryFilePath,
            action: .modified,
            kind: .file
        )
    )

    let request = try #require(store.fileHistoryRequest)
    let expected = "문서/주간보고서.hwp".decomposedStringWithCanonicalMapping
    #expect(Data(request.relativePath.utf8) == Data(expected.utf8))
}

@MainActor
@Test func switchedProjectRejectsLateRevisionContentsBeforeFileMutation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-restore-project-switch-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let firstRoot = root.appendingPathComponent("first", isDirectory: true)
    let secondRoot = root.appendingPathComponent("second", isDirectory: true)
    let relativePath = "forms/report.xlsx"
    let firstFile = firstRoot.appendingPathComponent(relativePath)
    let secondFile = secondRoot.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: firstFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let firstContents = Data("first-current".utf8)
    let secondContents = Data("second-current".utf8)
    try firstContents.write(to: firstFile)
    try secondContents.write(to: secondFile)
    let first = SVNProject(name: "first", path: firstRoot.path)
    let second = SVNProject(name: "second", path: secondRoot.path)
    let clientFixture = try DelayedSVNExecutableFixture(contents: Data("historical".utf8))
    defer { clientFixture.remove() }
    let store = revisionRestoreStore(projects: [first, second], client: clientFixture.client)
    store.fileHistoryRequest = FileHistoryRequest(
        projectID: first.id,
        relativePath: relativePath
    )
    store.requestHistoryRevisionRestore(revision: "9")
    let request = try #require(store.recoveryState.historyRevisionRestoreRequest)

    let restore = Task { await store.confirmHistoryRevisionRestore(request) }
    await clientFixture.waitUntilStarted()
    store.selectedProjectID = second.id
    try clientFixture.release()

    #expect(await restore.value == false)
    #expect(try Data(contentsOf: firstFile) == firstContents)
    #expect(try Data(contentsOf: secondFile) == secondContents)
    #expect(store.notice == nil)
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func switchedProjectRejectsCapturedRevisionRestoreBeforeSVNRead() async throws {
    let first = SVNProject(name: "first", path: "/tmp/revision-restore-confirm-first")
    let second = SVNProject(name: "second", path: "/tmp/revision-restore-confirm-second")
    let clientFixture = try DelayedSVNExecutableFixture(contents: Data("historical".utf8))
    defer { clientFixture.remove() }
    let store = revisionRestoreStore(projects: [first, second], client: clientFixture.client)
    let fileHistoryRequest = FileHistoryRequest(
        projectID: first.id,
        relativePath: "report.xlsx"
    )
    store.fileHistoryRequest = fileHistoryRequest
    store.requestHistoryRevisionRestore(revision: "9")
    let request = try #require(store.recoveryState.historyRevisionRestoreRequest)

    store.selectedProjectID = second.id
    store.fileHistoryRequest = fileHistoryRequest
    store.recoveryState.historyRevisionRestoreRequest = request
    try clientFixture.release()
    let didRestore = await store.confirmHistoryRevisionRestore(request)

    #expect(!didRestore)
    #expect(try clientFixture.invocationCount() == 0)
    #expect(store.recoveryState.historyRevisionRestoreRequest == nil)
    #expect(store.notice == nil)
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func revisionSaveRejectsDuplicateExecutionWhileExportIsRunning() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-save-duplicate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destinations", isDirectory: true)
    try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    let project = SVNProject(name: "project", path: workingCopy.path)
    let clientFixture = try DelayedSVNExecutableFixture(contents: Data([0x00, 0xFF, 0x80]))
    defer { clientFixture.remove() }
    let store = revisionRestoreStore(projects: [project], client: clientFixture.client)
    let firstDestination = destinationDirectory.appendingPathComponent("first.xlsx")
    let secondDestination = destinationDirectory.appendingPathComponent("second.xlsx")
    let fileHistoryRequest = FileHistoryRequest(
        projectID: project.id,
        relativePath: "report.xlsx"
    )
    store.fileHistoryRequest = fileHistoryRequest
    let firstRequest = HistoryRevisionSaveRequest(
        fileHistoryRequestID: fileHistoryRequest.id,
        projectID: project.id,
        relativePath: fileHistoryRequest.relativePath,
        revision: "5",
        destinationURL: firstDestination
    )
    let secondRequest = HistoryRevisionSaveRequest(
        fileHistoryRequestID: fileHistoryRequest.id,
        projectID: project.id,
        relativePath: fileHistoryRequest.relativePath,
        revision: "5",
        destinationURL: secondDestination
    )

    let firstSave = Task {
        await store.saveHistoryRevision(firstRequest)
    }
    await clientFixture.waitUntilStarted()
    let duplicateResult = await store.saveHistoryRevision(secondRequest)

    #expect(store.isHistoryRevisionOperationRunning)
    #expect(duplicateResult == false)
    #expect(try clientFixture.invocationCount() == 1)
    try clientFixture.release()
    #expect(await firstSave.value)
    #expect(!store.isHistoryRevisionOperationRunning)
    #expect(try Data(contentsOf: firstDestination) == Data([0x00, 0xFF, 0x80]))
    #expect(!FileManager.default.fileExists(atPath: secondDestination.path))
}

@MainActor
@Test func demoModeRejectsRevisionSaveWithoutLaunchingLiveSVN() async throws {
    let store = ProjectStore.demo()
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("demo-revision-save-\(UUID().uuidString).xlsx")
    defer { try? FileManager.default.removeItem(at: destination) }
    let project = try #require(store.selectedProject)
    let fileHistoryRequest = FileHistoryRequest(
        projectID: project.id,
        relativePath: "Resources/Quarterly.xlsx"
    )
    store.fileHistoryRequest = fileHistoryRequest
    let request = HistoryRevisionSaveRequest(
        fileHistoryRequestID: fileHistoryRequest.id,
        projectID: project.id,
        relativePath: fileHistoryRequest.relativePath,
        revision: "1845",
        destinationURL: destination
    )

    let didSave = await store.saveHistoryRevision(request)

    #expect(!didSave)
    #expect(
        store.errorMessage
            == AppLanguage.current.localized(.ui.revision.projectSvnClientDoesNotSupportReadingHistoricalFileRevisions)
    )
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@MainActor
@Test func switchedProjectRejectsCapturedRevisionSaveRequestBeforeSVNExport() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-save-project-switch-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
    let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
    try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
    let first = SVNProject(name: "first", path: firstDirectory.path)
    let second = SVNProject(name: "second", path: secondDirectory.path)
    let clientFixture = try DelayedSVNExecutableFixture(contents: Data("historical".utf8))
    defer { clientFixture.remove() }
    let store = revisionRestoreStore(projects: [first, second], client: clientFixture.client)
    let fileHistoryRequest = FileHistoryRequest(
        projectID: first.id,
        relativePath: "report.xlsx"
    )
    store.fileHistoryRequest = fileHistoryRequest
    let destination = destinationDirectory.appendingPathComponent("report.xlsx")
    let request = HistoryRevisionSaveRequest(
        fileHistoryRequestID: fileHistoryRequest.id,
        projectID: first.id,
        relativePath: fileHistoryRequest.relativePath,
        revision: "5",
        destinationURL: destination
    )

    store.selectedProjectID = second.id
    try clientFixture.release()
    let didSave = await store.saveHistoryRevision(request)

    #expect(!didSave)
    #expect(try clientFixture.invocationCount() == 0)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(store.notice == nil)
    #expect(store.errorMessage == nil)
}

@Test func revisionRestoreRecreatesDeletedWorkingFileWithoutRecoveryCopy() async throws {
    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-restore-deleted-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }
    let workingCopy = fixtureRoot.appendingPathComponent("working-copy", isDirectory: true)
    let backupRoot = fixtureRoot.appendingPathComponent("backups", isDirectory: true)
    let workingFile = workingCopy.appendingPathComponent("forms/report.hwp")
    let historical = Data([0x48, 0x57, 0x50, 0x00, 0x02, 0x80])
    try FileManager.default.createDirectory(
        at: workingFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let service = RevisionFileService(
        backupRootURL: backupRoot,
        replaceItem: { _, _ in
            Issue.record("없는 파일을 교체하려 했습니다")
        }
    )

    let result = try await service.restoreWorkingFile(
        contents: historical,
        workingCopyPath: workingCopy.path,
        relativePath: "forms/report.hwp",
        projectID: UUID(),
        revision: "17"
    )

    #expect(result.recoveryURL == nil)
    #expect(try Data(contentsOf: workingFile) == historical)
    let siblings = try FileManager.default.contentsOfDirectory(
        at: workingFile.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    )
    #expect(!siblings.contains { $0.lastPathComponent.hasPrefix(".svn-mac-revision-restore-") })
}

@Test func revisionRestoreRecreatesParentFolderDeletedWithTheFile() async throws {
    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-restore-deleted-parent-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }
    let workingCopy = fixtureRoot.appendingPathComponent("working-copy", isDirectory: true)
    let backupRoot = fixtureRoot.appendingPathComponent("backups", isDirectory: true)
    try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)
    let historical = Data("지난주 양식".utf8)

    let result = try await RevisionFileService(backupRootURL: backupRoot).restoreWorkingFile(
        contents: historical,
        workingCopyPath: workingCopy.path,
        relativePath: "공유/양식/report.hwp",
        projectID: UUID(),
        revision: "4"
    )

    #expect(result.recoveryURL == nil)
    #expect(
        try Data(contentsOf: workingCopy.appendingPathComponent("공유/양식/report.hwp")) == historical
    )
}

@Test func revisionRestoreRejectsPathWhoseParentIsRegularFile() async throws {
    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("revision-restore-file-parent-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }
    let workingCopy = fixtureRoot.appendingPathComponent("working-copy", isDirectory: true)
    let backupRoot = fixtureRoot.appendingPathComponent("backups", isDirectory: true)
    try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)
    let blocker = workingCopy.appendingPathComponent("forms")
    try Data("not a folder".utf8).write(to: blocker)

    await #expect(throws: RevisionFileError.unsafeWorkingFileParent) {
        try await RevisionFileService(backupRootURL: backupRoot).restoreWorkingFile(
            contents: Data("historical".utf8),
            workingCopyPath: workingCopy.path,
            relativePath: "forms/report.hwp",
            projectID: UUID(),
            revision: "4"
        )
    }
    #expect(try Data(contentsOf: blocker) == Data("not a folder".utf8))
}

private final class ReplacementObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var observedOriginalDestination: Bool {
        lock.withLock { value }
    }

    func record(_ value: Bool) {
        lock.withLock { self.value = value }
    }
}

@MainActor
private func revisionRestoreStore(
    projects: [SVNProject],
    client: any SVNClientServing = SVNClient()
) -> ProjectStore {
    ProjectStore(
        client: client,
        credentialStore: RevisionRestoreCredentialStore(),
        persistence: RevisionRestorePersistence(projects: projects),
        projectAccessManager: RevisionRestoreAccessManager(),
        projectPathChecker: RevisionRestorePathChecker(),
        volumeNormalizationProbe: RevisionRestoreVolumeProbe(),
        settingsDefaults: UserDefaults(suiteName: "revision-restore-\(UUID().uuidString)")!,
        updateBadgeRefreshInterval: nil
    )
}

private final class DelayedSVNExecutableFixture: @unchecked Sendable {
    let root: URL
    let client: SVNClient
    private let releaseURL: URL
    private let invocationURL: URL
    private let startedEvent: AsyncTestEvent
    private let startedSource: DispatchSourceFileSystemObject

    init(contents: Data) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("revision-injected-client-\(UUID().uuidString)", isDirectory: true)
        let executableURL = root.appendingPathComponent("svn-fixture")
        let contentsURL = root.appendingPathComponent("contents")
        let configURL = root.appendingPathComponent("config", isDirectory: true)
        let startedURL = root.appendingPathComponent("started")
        releaseURL = root.appendingPathComponent("release")
        invocationURL = root.appendingPathComponent("invocations")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try contents.write(to: contentsURL)
        try Data().write(to: startedURL)
        let startedDescriptor = open(startedURL.path, O_EVTONLY)
        guard startedDescriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let startedEvent = AsyncTestEvent()
        let startedSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: startedDescriptor,
            eventMask: .write,
            queue: .global()
        )
        self.startedEvent = startedEvent
        self.startedSource = startedSource
        startedSource.setEventHandler { startedEvent.signal() }
        startedSource.setCancelHandler { close(startedDescriptor) }
        startedSource.resume()
        let script = """
        #!/bin/sh
        command_name=""
        destination=""
        for argument in "$@"; do
          case "$argument" in
            cat|export) command_name="$argument" ;;
          esac
          destination="$argument"
        done
        printf x >> \(Self.shellQuote(invocationURL.path))
        printf x >> \(Self.shellQuote(startedURL.path))
        while [ ! -e \(Self.shellQuote(releaseURL.path)) ]; do sleep 0.01; done
        if [ "$command_name" = "cat" ]; then
          /bin/cat \(Self.shellQuote(contentsURL.path))
          exit 0
        fi
        if [ "$command_name" = "export" ]; then
          /bin/cp \(Self.shellQuote(contentsURL.path)) "$destination"
          exit 0
        fi
        exit 64
        """
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        client = SVNClient(
            executablePath: executableURL.path,
            configDirectoryPath: configURL.path
        )
    }

    func waitUntilStarted() async {
        await startedEvent.wait()
    }

    func release() throws {
        try Data().write(to: releaseURL)
    }

    func invocationCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: invocationURL.path) else { return 0 }
        return try Data(contentsOf: invocationURL).count
    }

    func remove() {
        startedSource.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

private final class AsyncTestEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        lock.lock()
        guard !isSignaled else {
            lock.unlock()
            return
        }
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isSignaled {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

private struct RevisionRestoreCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct RevisionRestorePersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private final class RevisionRestoreAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

private struct RevisionRestorePathChecker: ProjectPathChecking {
    func directoryExists(at _: String) -> Bool { true }
}

private actor RevisionRestoreVolumeProbe: VolumeNormalizationProbing {
    func preservesPrecomposedFilenames(at _: String) async -> Bool? { true }
}

private final class RevisionSVNFixture {
    let root: URL
    let workingCopy: URL
    let externalDestination: URL
    let client: SVNClient
    private let svnPath: String

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("revision-restore-svn-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        externalDestination = root.appendingPathComponent("outside-working-copy", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalDestination, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path])
        let repositoryURL = repository.absoluteString + "trunk"
        _ = try Self.run(svnPath, ["mkdir", repositoryURL, "-m", "trunk"])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    func write(_ data: Data, relativePath: String) throws {
        let destination = workingCopy.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    func addAndCommit(message: String) throws {
        _ = try Self.run(svnPath, ["add", "--force", "."], currentDirectory: workingCopy)
        try commit(message: message)
    }

    func commit(message: String) throws {
        _ = try Self.run(svnPath, ["commit", "-m", message], currentDirectory: workingCopy)
    }

    func delete(relativePath: String) throws {
        _ = try Self.run(svnPath, ["delete", relativePath], currentDirectory: workingCopy)
    }

    func update() throws {
        _ = try Self.run(svnPath, ["update"], currentDirectory: workingCopy)
    }

    func status() throws -> String {
        try Self.run(svnPath, ["status"], currentDirectory: workingCopy)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw RevisionSVNFixtureError(
                command: ([executable] + arguments).joined(separator: " "),
                output: String(decoding: outputData, as: UTF8.self),
                error: String(decoding: errorData, as: UTF8.self)
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

private struct RevisionSVNFixtureError: Error, CustomStringConvertible {
    let command: String
    let output: String
    let error: String
    var description: String { "\(command)\n\(output)\n\(error)" }
}
