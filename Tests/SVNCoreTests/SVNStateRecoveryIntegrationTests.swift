import Foundation
import Testing
@testable import SVNCore

@Test func realSVNParsesModifiedAndConflictedDirectoryProperties() async throws {
    let fixture = try SVNStateIntegrationFixture()
    defer { fixture.remove() }

    _ = try runSVNStateCommand(
        fixture.svnPath,
        ["propset", "svn:ignore", "*.from-a", "."],
        currentDirectory: fixture.firstWorkingCopy
    )
    let modified = try #require(
        try await fixture.client.status(at: fixture.firstWorkingCopy.path)
            .first(where: { $0.path == "." })
    )
    #expect(modified.propertyState == .modified)
    #expect(modified.isSelectableForCommit)

    _ = try runSVNStateCommand(
        fixture.svnPath,
        ["commit", "-m", "property from a"],
        currentDirectory: fixture.firstWorkingCopy
    )
    _ = try runSVNStateCommand(
        fixture.svnPath,
        ["propset", "svn:ignore", "*.from-b", "."],
        currentDirectory: fixture.secondWorkingCopy
    )
    _ = try runSVNStateCommand(
        fixture.svnPath,
        ["update"],
        currentDirectory: fixture.secondWorkingCopy
    )

    let conflicted = try #require(
        try await fixture.client.status(at: fixture.secondWorkingCopy.path)
            .first(where: { $0.path == "." })
    )
    #expect(conflicted.item.rawValue == "normal")
    #expect(conflicted.propertyState == .conflicted)
    #expect(!conflicted.isSelectableForCommit)
}

@Test func realSVNParsesObstructedWorkingCopyNode() async throws {
    let fixture = try SVNStateIntegrationFixture(repositoryDirectoryName: "versioned-dir")
    defer { fixture.remove() }
    let versionedDirectory = fixture.firstWorkingCopy.appendingPathComponent(
        "versioned-dir",
        isDirectory: true
    )
    let displacedDirectory = fixture.firstWorkingCopy.appendingPathComponent(
        "versioned-dir-backup",
        isDirectory: true
    )
    try FileManager.default.moveItem(at: versionedDirectory, to: displacedDirectory)
    try Data().write(to: versionedDirectory)

    let entry = try #require(
        try await fixture.client.status(at: fixture.firstWorkingCopy.path)
            .first(where: { $0.path == "versioned-dir" })
    )

    #expect(entry.item == .obstructed)
    #expect(entry.item.rawValue == "obstructed")
}

@Test func realSVNCleanupClearsWorkingCopyLock() async throws {
    let fixture = try SVNStateIntegrationFixture()
    defer { fixture.remove() }
    let sqlitePath = try #require(svnStateExecutable(at: ["/usr/bin/sqlite3"]))
    let database = fixture.firstWorkingCopy
        .appendingPathComponent(".svn/wc.db", isDirectory: false)
    _ = try runSVNStateCommand(
        sqlitePath,
        [database.path, "INSERT INTO WC_LOCK (wc_id, local_dir_relpath, locked_levels) VALUES (1, '', -1);"]
    )

    let lockedUpdate = runSVNStateCommandResult(
        fixture.svnPath,
        ["update"],
        currentDirectory: fixture.firstWorkingCopy
    )
    #expect(lockedUpdate.exitCode != 0)
    #expect(lockedUpdate.error.contains("E155004"))
    #expect(SVNClient.isWorkingCopyLockedError(lockedUpdate.error))

    _ = try await fixture.client.cleanup(at: fixture.firstWorkingCopy.path)

    _ = try runSVNStateCommand(
        fixture.svnPath,
        ["update"],
        currentDirectory: fixture.firstWorkingCopy
    )
}

@Test func realSVNForceUnlockBreaksLockFromAnotherWorkingCopy() async throws {
    let fixture = try SVNStateIntegrationFixture(repositoryFileName: "locked.txt")
    defer { fixture.remove() }
    let firstPath = fixture.firstWorkingCopy.appendingPathComponent("locked.txt").path
    let secondPath = fixture.secondWorkingCopy.appendingPathComponent("locked.txt").path
    _ = try runSVNStateCommand(fixture.svnPath, ["lock", firstPath, "-m", "editing"])

    await #expect(throws: SVNError.self) {
        _ = try await fixture.client.unlock(
            at: fixture.secondWorkingCopy.path,
            relativePath: "locked.txt"
        )
    }

    _ = try await fixture.client.unlock(
        at: fixture.secondWorkingCopy.path,
        relativePath: "locked.txt",
        force: true
    )

    let information = try runSVNStateCommand(fixture.svnPath, ["info", "--xml", secondPath])
    #expect(!information.contains("<lock>"))
}

private struct SVNStateIntegrationFixture {
    let root: URL
    let firstWorkingCopy: URL
    let secondWorkingCopy: URL
    let svnPath: String
    let client: SVNClient

    init(repositoryDirectoryName: String? = nil, repositoryFileName: String? = nil) throws {
        let fileManager = FileManager.default
        svnPath = try #require(svnStateExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(svnStateExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-state-recovery-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let importDirectory = root.appendingPathComponent("import", isDirectory: true)
        firstWorkingCopy = root.appendingPathComponent("first", isDirectory: true)
        secondWorkingCopy = root.appendingPathComponent("second", isDirectory: true)
        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        if let repositoryDirectoryName {
            try fileManager.createDirectory(
                at: importDirectory.appendingPathComponent(repositoryDirectoryName, isDirectory: true),
                withIntermediateDirectories: false
            )
        }
        if let repositoryFileName {
            try Data("base\n".utf8).write(to: importDirectory.appendingPathComponent(repositoryFileName))
        }
        _ = try runSVNStateCommand(svnadminPath, ["create", repository.path])
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try runSVNStateCommand(
            svnPath,
            ["import", importDirectory.path, repositoryURL, "-m", "initial"]
        )
        _ = try runSVNStateCommand(svnPath, ["checkout", repositoryURL, firstWorkingCopy.path])
        _ = try runSVNStateCommand(svnPath, ["checkout", repositoryURL, secondWorkingCopy.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func svnStateExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runSVNStateCommand(
    _ executable: String,
    _ arguments: [String],
    currentDirectory: URL? = nil
) throws -> String {
    let result = runSVNStateCommandResult(
        executable,
        arguments,
        currentDirectory: currentDirectory
    )
    guard result.exitCode == 0 else {
        throw SVNStateCommandError(
            executable: executable,
            arguments: arguments,
            output: result.output,
            error: result.error
        )
    }
    return result.output
}

private func runSVNStateCommandResult(
    _ executable: String,
    _ arguments: [String],
    currentDirectory: URL? = nil
) -> SVNStateCommandResult {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    process.standardOutput = output
    process.standardError = error
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return SVNStateCommandResult(output: "", error: String(describing: error), exitCode: -1)
    }
    return SVNStateCommandResult(
        output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        error: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        exitCode: process.terminationStatus
    )
}

private struct SVNStateCommandResult {
    let output: String
    let error: String
    let exitCode: Int32
}

private struct SVNStateCommandError: Error, CustomStringConvertible {
    let executable: String
    let arguments: [String]
    let output: String
    let error: String

    var description: String {
        "Command failed: \(([executable] + arguments).joined(separator: " "))\n\(output)\n\(error)"
    }
}
