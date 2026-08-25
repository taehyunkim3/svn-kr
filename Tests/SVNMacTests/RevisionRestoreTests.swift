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
        allowUntrustedServerCertificate: false
    )

    #expect(try Data(contentsOf: destination) == original)
    #expect(try Data(contentsOf: fixture.workingCopy.appendingPathComponent("document.xlsx")) == changed)
}

@MainActor
@Test func realSVNRevisionRestorePreservesCurrentBinaryAndLeavesHistoricalBytesModified() async throws {
    let fixture = try RevisionSVNFixture()
    defer { fixture.remove() }
    let original = Data([0x00, 0x50, 0x4B, 0x03, 0x04, 0xFF, 0x0A, 0x80])
    let current = Data([0x48, 0x57, 0x50, 0x00, 0xFE])
    try fixture.write(original, relativePath: "document.xlsx")
    try fixture.addAndCommit(message: "original")
    try fixture.write(current, relativePath: "document.xlsx")
    try fixture.commit(message: "changed")
    let project = SVNProject(name: "binary", path: fixture.workingCopy.path)
    let backupRoot = fixture.root.appendingPathComponent("revision-backups", isDirectory: true)
    let store = revisionRestoreStore(projects: [project])
    store.recoveryState.historyRevisionClient = fixture.client
    store.recoveryState.revisionFileService = RevisionFileService(backupRootURL: backupRoot)
    store.requestHistoryRevisionRestore(revision: "2", relativePath: "document.xlsx")
    let request = try #require(store.recoveryState.historyRevisionRestoreRequest)

    #expect(await store.confirmHistoryRevisionRestore(request))

    let workingFile = fixture.workingCopy.appendingPathComponent("document.xlsx")
    #expect(try Data(contentsOf: workingFile) == original)
    #expect(store.visibleStatuses.contains { $0.path == "document.xlsx" && $0.item == .modified })
    let projectBackup = backupRoot.appendingPathComponent(project.id.uuidString, isDirectory: true)
    let session = try #require(
        FileManager.default.contentsOfDirectory(
            at: projectBackup,
            includingPropertiesForKeys: nil
        ).first
    )
    let recoveryFile = try #require(
        FileManager.default.contentsOfDirectory(
            at: session,
            includingPropertiesForKeys: nil
        ).first
    )
    #expect(try Data(contentsOf: recoveryFile) == current)
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
    #expect(try Data(contentsOf: result.recoveryURL) == current)
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

    store.requestHistoryRevisionRestore(revision: "31", relativePath: "forms/report.xlsx")

    let request = try #require(store.recoveryState.historyRevisionRestoreRequest)
    #expect(request.projectID == project.id)
    #expect(request.revision == "31")
    #expect(request.relativePath == "forms/report.xlsx")
    #expect(store.recoveryState.historyRevisionOperation == nil)
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
    let gate = RevisionContentGate()
    let client = DelayedHistoryRevisionClient(gate: gate, contents: Data("historical".utf8))
    let store = revisionRestoreStore(projects: [first, second])
    store.recoveryState.historyRevisionClient = client
    store.requestHistoryRevisionRestore(revision: "9", relativePath: relativePath)
    let request = try #require(store.recoveryState.historyRevisionRestoreRequest)

    let restore = Task { await store.confirmHistoryRevisionRestore(request) }
    await gate.waitUntilStarted()
    store.selectedProjectID = second.id
    await gate.release()

    #expect(await restore.value == false)
    #expect(try Data(contentsOf: firstFile) == firstContents)
    #expect(try Data(contentsOf: secondFile) == secondContents)
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
    let gate = RevisionContentGate()
    let client = DelayedRevisionExportClient(gate: gate, contents: Data([0x00, 0xFF, 0x80]))
    let store = revisionRestoreStore(projects: [project])
    store.recoveryState.historyRevisionClient = client
    let firstDestination = destinationDirectory.appendingPathComponent("first.xlsx")
    let secondDestination = destinationDirectory.appendingPathComponent("second.xlsx")

    let firstSave = Task {
        await store.saveHistoryRevision(
            revision: "5",
            relativePath: "report.xlsx",
            to: firstDestination
        )
    }
    await gate.waitUntilStarted()
    let duplicateResult = await store.saveHistoryRevision(
        revision: "5",
        relativePath: "report.xlsx",
        to: secondDestination
    )

    #expect(store.isHistoryRevisionOperationRunning)
    #expect(duplicateResult == false)
    #expect(await client.exportCount == 1)
    await gate.release()
    #expect(await firstSave.value)
    #expect(!store.isHistoryRevisionOperationRunning)
    #expect(try Data(contentsOf: firstDestination) == Data([0x00, 0xFF, 0x80]))
    #expect(!FileManager.default.fileExists(atPath: secondDestination.path))
}

private actor RevisionContentGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
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

private actor DelayedHistoryRevisionClient: HistoryRevisionClient {
    let gate: RevisionContentGate
    let contents: Data

    init(gate: RevisionContentGate, contents: Data) {
        self.gate = gate
        self.contents = contents
    }

    func fileContents(
        at _: String,
        relativePath _: String,
        revision _: String,
        credentials _: SVNCredentials?,
        allowUntrustedServerCertificate _: Bool,
        allowedServerCertificateFailures _: Set<SVNServerCertificateFailure>
    ) async throws -> Data {
        await gate.wait()
        return contents
    }

    func export(
        at _: String,
        relativePath _: String,
        revision _: String,
        destinationPath _: String,
        force _: Bool,
        credentials _: SVNCredentials?,
        allowUntrustedServerCertificate _: Bool,
        allowedServerCertificateFailures _: Set<SVNServerCertificateFailure>
    ) async throws -> String { "" }
}

private actor DelayedRevisionExportClient: HistoryRevisionClient {
    let gate: RevisionContentGate
    let contents: Data
    private(set) var exportCount = 0

    init(gate: RevisionContentGate, contents: Data) {
        self.gate = gate
        self.contents = contents
    }

    func fileContents(
        at _: String,
        relativePath _: String,
        revision _: String,
        credentials _: SVNCredentials?,
        allowUntrustedServerCertificate _: Bool,
        allowedServerCertificateFailures _: Set<SVNServerCertificateFailure>
    ) async throws -> Data { contents }

    func export(
        at _: String,
        relativePath _: String,
        revision _: String,
        destinationPath: String,
        force _: Bool,
        credentials _: SVNCredentials?,
        allowUntrustedServerCertificate _: Bool,
        allowedServerCertificateFailures _: Set<SVNServerCertificateFailure>
    ) async throws -> String {
        exportCount += 1
        await gate.wait()
        try contents.write(to: URL(fileURLWithPath: destinationPath))
        return ""
    }
}

@MainActor
private func revisionRestoreStore(projects: [SVNProject]) -> ProjectStore {
    ProjectStore(
        credentialStore: RevisionRestoreCredentialStore(),
        persistence: RevisionRestorePersistence(projects: projects),
        projectAccessManager: RevisionRestoreAccessManager(),
        projectPathChecker: RevisionRestorePathChecker(),
        volumeNormalizationProbe: RevisionRestoreVolumeProbe(),
        settingsDefaults: UserDefaults(suiteName: "revision-restore-\(UUID().uuidString)")!,
        updateBadgeRefreshInterval: nil
    )
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
