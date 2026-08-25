import Foundation
import SVNCore
import Testing
@testable import SVNMac

@MainActor
@Test func partialCommitDoesNotCreateFalseUpdateRequirement() async throws {
    let fixture = try MixedRevisionUpdateFixture()
    defer { fixture.remove() }

    try fixture.modify("a.txt", in: fixture.workingCopy, contents: "user\n")
    try fixture.modify("b.txt", in: fixture.workingCopy, contents: "pending\n")
    try fixture.commit("a.txt", in: fixture.workingCopy, message: "partial")

    let revision = try await fixture.client.workingCopyRevision(at: fixture.workingCopy.path)
    #expect(revision.isMixed)
    #expect(!(try await fixture.client.workingCopyIsOutOfDate(at: fixture.workingCopy.path)))
    #expect(try await fixture.client.incomingCommits(at: fixture.workingCopy.path) == [])

    let project = SVNProject(name: "혼합 리비전", path: fixture.workingCopy.path)
    let store = ProjectStore(
        client: fixture.client,
        credentialStore: MixedRevisionCredentialStore(),
        persistence: MixedRevisionProjectPersistence(projects: [project]),
        updateBadgeRefreshInterval: nil
    )

    await store.refresh()

    #expect(store.isWorkingCopyOutOfDate == false)
    #expect(store.projectSummaries[project.id]?.needsUpdate == false)
}

@Test func incomingCommitsExcludeOwnPartialCommitAndKeepRemoteCommit() async throws {
    let fixture = try MixedRevisionUpdateFixture()
    defer { fixture.remove() }

    try fixture.modify("a.txt", in: fixture.workingCopy, contents: "user\n")
    try fixture.commit("a.txt", in: fixture.workingCopy, message: "partial")
    try fixture.modify("b.txt", in: fixture.otherWorkingCopy, contents: "other\n")
    try fixture.commit("b.txt", in: fixture.otherWorkingCopy, message: "remote")

    #expect(try await fixture.client.workingCopyIsOutOfDate(at: fixture.workingCopy.path))
    let incoming = try await fixture.client.incomingCommits(at: fixture.workingCopy.path)
    #expect(incoming.map(\.revision) == ["3"])
    #expect(incoming.map(\.message) == ["remote"])
}

@MainActor
@Test func directoryPropertyCommitCanUpdateAndRetryWithoutLosingCommitInput() async throws {
    let fixture = try MixedRevisionUpdateFixture()
    defer { fixture.remove() }

    try fixture.modify("a.txt", in: fixture.workingCopy, contents: "user\n")
    try fixture.commit("a.txt", in: fixture.workingCopy, message: "partial")
    _ = try await fixture.client.setProperty(
        named: "svn:ignore",
        value: Data("build\n".utf8),
        at: fixture.workingCopy.path,
        relativePath: "."
    )

    let project = SVNProject(name: "속성 커밋", path: fixture.workingCopy.path)
    let store = ProjectStore(
        client: fixture.client,
        credentialStore: MixedRevisionCredentialStore(),
        persistence: MixedRevisionProjectPersistence(projects: [project]),
        updateBadgeRefreshInterval: nil
    )
    await store.refresh()
    store.selectedPaths = ["."]

    #expect(!(await store.commit(message: "무시 규칙 추가")))
    let recovery = try #require(store.recoveryState.outOfDateCommitRecoveryRequest)
    #expect(recovery.message == "무시 규칙 추가")
    #expect(recovery.paths == ["."])
    #expect(store.isShowingUpdatePreview)
    #expect(store.errorMessage == nil)

    await store.update()

    #expect(store.recoveryState.outOfDateCommitRecoveryRequest == nil)
    #expect(store.lastCompletedCommitMessage == "무시 규칙 추가")
    #expect(store.selectedPaths.isEmpty)
    _ = try await fixture.client.update(at: fixture.otherWorkingCopy.path)
    let property = try await fixture.client.propertyValue(
        named: "svn:ignore",
        at: fixture.otherWorkingCopy.path,
        relativePath: "."
    )
    #expect(property == Data("build\n".utf8))
}

private final class MixedRevisionUpdateFixture: @unchecked Sendable {
    let root: URL
    let workingCopy: URL
    let otherWorkingCopy: URL
    let client: SVNClient

    private let svnPath: String
    private let fileManager = FileManager.default

    init() throws {
        svnPath = try #require(Self.executable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.executable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-mixed-revision-update-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let imported = root.appendingPathComponent("import", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        otherWorkingCopy = root.appendingPathComponent("other-working-copy", isDirectory: true)
        try fileManager.createDirectory(at: imported, withIntermediateDirectories: true)
        try Data("base-a\n".utf8).write(to: imported.appendingPathComponent("a.txt"))
        try Data("base-b\n".utf8).write(to: imported.appendingPathComponent("b.txt"))
        _ = try Self.run(svnadminPath, ["create", repository.path], at: root)
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try Self.run(svnPath, ["import", imported.path, repositoryURL, "-m", "initial"], at: root)
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path], at: root)
        _ = try Self.run(svnPath, ["checkout", repositoryURL, otherWorkingCopy.path], at: root)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config").path
        )
    }

    func modify(_ path: String, in workingCopy: URL, contents: String) throws {
        try Data(contents.utf8).write(to: workingCopy.appendingPathComponent(path))
    }

    func commit(_ path: String, in workingCopy: URL, message: String) throws {
        _ = try Self.run(
            svnPath,
            ["commit", workingCopy.appendingPathComponent(path).path, "-m", message],
            at: root
        )
    }

    func remove() {
        try? fileManager.removeItem(at: root)
    }

    private static func executable(at candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ executable: String, _ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw MixedRevisionCommandError(
                command: ([executable] + arguments).joined(separator: " "),
                output: String(decoding: stdout + stderr, as: UTF8.self)
            )
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}

private struct MixedRevisionCommandError: LocalizedError {
    let command: String
    let output: String

    var errorDescription: String? { "Command failed: \(command)\n\(output)" }
}

private struct MixedRevisionCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private final class MixedRevisionProjectPersistence: ProjectPersisting {
    private let projects: [SVNProject]

    init(projects: [SVNProject]) {
        self.projects = projects
    }

    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}
