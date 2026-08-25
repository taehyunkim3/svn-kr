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
        #expect(await store.commitSelectedChanges(message: "Finder 삭제"))
        #expect(try fixture.repositoryFiles().isEmpty)
        #expect(try fixture.workingCopyStatus().isEmpty)
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
    let filePath = "월간 보고서.txt"
    let project: SVNProject
    let client: SVNClient

    var fileURL: URL { workingCopy.appendingPathComponent(filePath) }

    private let svnPath: String
    private let repositoryURL: String

    init() throws {
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
        try Data("보고서\n".utf8).write(to: fileURL)
        _ = try Self.run(svnPath, ["add", fileURL.path])
        _ = try Self.run(svnPath, ["commit", fileURL.path, "-m", "보고서 추가"])
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
