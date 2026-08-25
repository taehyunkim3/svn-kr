import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Suite("MissingCommitSelectionTests")
struct MissingCommitSelectionTests {
    @Test func selectAllIncludesMissingRepositoryItems() {
        let modified = SVNStatusEntry(path: "edited.txt", item: .modified, revision: "10")
        let missing = SVNStatusEntry(path: "removed.txt", item: .missing, revision: "10")
        let missingAddition = SVNStatusEntry(path: "never-added.txt", item: .missing, revision: "-1")

        let selected = TemporaryFilePolicy.automaticallySelectedEntries([
            modified,
            missing,
            missingAddition,
        ])

        #expect(selected.map(\.path) == ["edited.txt", "removed.txt"])
    }

    @Test func missingRepositoryItemsAreCommitEligible() {
        let missing = SVNStatusEntry(path: "removed.txt", item: .missing, revision: "10")
        let missingAddition = SVNStatusEntry(path: "never-added.txt", item: .missing, revision: nil)

        let eligible = TemporaryFilePolicy.commitEligibleEntries(
            [missing, missingAddition],
            hideTemporaryFiles: true
        )

        #expect(eligible == [missing])
    }

    @MainActor
    @Test func finderDeletionCommitsRepositoryDeletionAndLocalRestoreStillWorks() async throws {
        let fixture = try MissingCommitFixture()
        defer { fixture.remove() }
        let defaultsName = "missing-commit-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = ProjectStore(
            client: fixture.client,
            persistence: MissingCommitProjectPersistence(project: fixture.project),
            settingsDefaults: defaults,
            hideTemporaryFiles: true,
            updateBadgeRefreshInterval: nil
        )

        try Data("수정된 보고서\n".utf8).write(to: fixture.fileURL)
        await store.refreshLocalWorkingCopy()
        store.selectedPaths = store.selectAllStatusPaths
        #expect(!store.prepareCommitConfirmation(message: "일반 수정"))
        await store.confirmRevert(RevertRequest(entry: try #require(store.statuses.first)))

        try FileManager.default.removeItem(at: fixture.fileURL)
        await store.refreshLocalWorkingCopy()
        let missing = try #require(store.statuses.first { $0.path == fixture.filePath })

        store.requestRevert(missing)
        await store.confirmRevert(try #require(store.revertRequest))

        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))

        try FileManager.default.removeItem(at: fixture.fileURL)
        await store.refreshLocalWorkingCopy()
        store.selectedPaths = store.selectAllStatusPaths

        #expect(store.selectedPaths == [fixture.filePath])
        #expect(store.prepareCommitConfirmation(message: "Finder 삭제"))
        let canceledRequest = try #require(store.commitConfirmationRequest)
        store.cancelCommitConfirmation()
        #expect(store.commitConfirmationRequest == nil)
        #expect(store.selectedPaths == [fixture.filePath])
        #expect(try fixture.repositoryFiles() == fixture.filePath + "\n")

        #expect(store.prepareCommitConfirmation(message: "Finder 삭제"))
        let confirmedRequest = try #require(store.commitConfirmationRequest)
        #expect(confirmedRequest.id != canceledRequest.id)
        #expect(await store.confirmCommit(confirmedRequest))
        #expect(try fixture.repositoryFiles().isEmpty)
        #expect(try fixture.workingCopyStatus().isEmpty)
    }

    @MainActor
    @Test func bulkRestoreRevivesMissingAndScheduledDeletionButExcludesModifiedFile() async throws {
        let fixture = try MissingCommitFixture(filePaths: [
            "Finder 삭제.txt",
            "SVN 삭제.txt",
            "수정.txt",
        ])
        defer { fixture.remove() }
        let defaultsName = "bulk-deletion-restore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let store = ProjectStore(
            client: fixture.client,
            persistence: MissingCommitProjectPersistence(project: fixture.project),
            settingsDefaults: defaults,
            hideTemporaryFiles: true,
            updateBadgeRefreshInterval: nil
        )

        try FileManager.default.removeItem(at: fixture.fileURL(for: "Finder 삭제.txt"))
        try fixture.scheduleDeletion("SVN 삭제.txt")
        try Data("수정됨\n".utf8).write(to: fixture.fileURL(for: "수정.txt"))
        await store.refreshLocalWorkingCopy()
        store.selectedPaths = store.selectAllStatusPaths

        #expect(store.prepareCommitConfirmation(message: "삭제 확인"))
        #expect(store.commitConfirmationRequest?.serverDeletionEntries.map(\.path) == [
            "Finder 삭제.txt",
            "SVN 삭제.txt",
        ])
        store.selectedCommitDeletionRestorePaths = [
            "Finder 삭제.txt",
            "SVN 삭제.txt",
            "수정.txt",
        ]
        store.requestCommitDeletionRestore()
        let restoreRequest = try #require(store.commitDeletionRestoreRequest)
        #expect(restoreRequest.paths == ["Finder 삭제.txt", "SVN 삭제.txt"])

        await store.confirmCommitDeletionRestore(restoreRequest)

        #expect(FileManager.default.fileExists(atPath: fixture.fileURL(for: "Finder 삭제.txt").path))
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL(for: "SVN 삭제.txt").path))
        #expect(store.commitConfirmationRequest?.serverDeletionEntries.isEmpty == true)
        #expect(store.selectedCommitDeletionRestorePaths.isEmpty)
        #expect(store.commitDeletionRestoreFailureMessage == nil)
    }

    @Test func partialRestoreResultKeepsEveryFailedPath() {
        let failedPaths = ["실패-8.txt", "실패-9.txt", "실패-10.txt"]
        let result = CommitDeletionRestoreResult(
            restoredPaths: (1 ... 7).map { "성공-\($0).txt" },
            failures: failedPaths.map { CommitDeletionRestoreFailure(path: $0, message: "E155010") }
        )

        #expect(result.restoredPaths.count == 7)
        #expect(result.failures.map(\.path) == failedPaths)
        #expect(result.localizedFailureMessage(.korean)?.contains("3개") == true)
        for path in failedPaths {
            #expect(result.localizedFailureMessage(.korean)?.contains(path) == true)
        }
    }
}

private struct MissingCommitProjectPersistence: ProjectPersisting {
    let project: SVNProject

    func loadProjects() -> [SVNProject] { [project] }
    func saveProjects(_: [SVNProject]) {}
}

private final class MissingCommitFixture {
    let root: URL
    let workingCopy: URL
    let filePaths: [String]
    let project: SVNProject
    let client: SVNClient

    var filePath: String { filePaths[0] }
    var fileURL: URL { fileURL(for: filePath) }

    private let svnPath: String
    private let repositoryURL: String

    init(filePaths: [String] = ["월간 보고서.txt"]) throws {
        self.filePaths = filePaths
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-missing-commit-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        repositoryURL = repository.absoluteString + "trunk"
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
        project = SVNProject(name: "Finder 삭제", path: workingCopy.path)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path])
        _ = try Self.run(svnPath, ["mkdir", repositoryURL, "-m", "초기화"])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path])
        for path in filePaths {
            try Data("보고서\n".utf8).write(to: fileURL(for: path))
        }
        _ = try Self.run(svnPath, ["add", "--force", workingCopy.path])
        _ = try Self.run(svnPath, ["commit", workingCopy.path, "-m", "보고서 추가"])
    }

    func fileURL(for path: String) -> URL {
        workingCopy.appendingPathComponent(path)
    }

    func scheduleDeletion(_ path: String) throws {
        _ = try Self.run(svnPath, ["delete", fileURL(for: path).path])
    }

    func repositoryFiles() throws -> String {
        try Self.run(svnPath, ["list", repositoryURL])
    }

    func workingCopyStatus() throws -> String {
        try Self.run(svnPath, ["status", workingCopy.path])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MissingCommitFixture",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return output
    }
}
