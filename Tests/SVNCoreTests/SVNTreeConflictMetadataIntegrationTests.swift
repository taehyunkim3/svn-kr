import Foundation
import Testing
@testable import SVNCore

@Test func parsesTreeConflictMetadataFromRealSVNInfo() throws {
    let fixture = try TreeConflictMetadataFixture()
    defer { fixture.remove() }

    let information = try runTreeConflictCommand(
        fixture.svnPath,
        ["info", "--xml", "tree.txt"],
        currentDirectory: fixture.localDeletionWorkingCopy
    )
    let details = try SVNXMLParser.conflictDetails(fromInfo: Data(information.utf8))

    #expect(details?.path == "tree.txt")
    #expect(details?.type == "tree")
    #expect(details?.operation == "update")
    #expect(details?.previousRevision == "1")
    #expect(details?.serverRevision == "2")
    #expect(details?.treeConflictAction == "edit")
    #expect(details?.treeConflictReason == "delete")
    #expect(details?.treeConflictKind == "file")
}

private struct TreeConflictMetadataFixture {
    let root: URL
    let localDeletionWorkingCopy: URL
    let svnPath: String

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(treeConflictExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(treeConflictExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-tree-conflict-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let importDirectory = root.appendingPathComponent("import", isDirectory: true)
        let serverEditWorkingCopy = root.appendingPathComponent("server-edit", isDirectory: true)
        localDeletionWorkingCopy = root.appendingPathComponent("local-delete", isDirectory: true)
        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        try Data("base\n".utf8).write(to: importDirectory.appendingPathComponent("tree.txt"))
        _ = try runTreeConflictCommand(svnadminPath, ["create", repository.path])
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try runTreeConflictCommand(svnPath, ["import", importDirectory.path, repositoryURL, "-m", "initial"])
        _ = try runTreeConflictCommand(svnPath, ["checkout", repositoryURL, serverEditWorkingCopy.path])
        _ = try runTreeConflictCommand(svnPath, ["checkout", repositoryURL, localDeletionWorkingCopy.path])
        try Data("base\nserver edit\n".utf8)
            .write(to: serverEditWorkingCopy.appendingPathComponent("tree.txt"))
        _ = try runTreeConflictCommand(
            svnPath,
            ["commit", serverEditWorkingCopy.appendingPathComponent("tree.txt").path, "-m", "server edit"]
        )
        _ = try runTreeConflictCommand(
            svnPath,
            ["delete", localDeletionWorkingCopy.appendingPathComponent("tree.txt").path]
        )
        _ = try runTreeConflictCommand(svnPath, ["update", localDeletionWorkingCopy.path])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func treeConflictExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runTreeConflictCommand(
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
        throw TreeConflictCommandError(
            executable: executable,
            arguments: arguments,
            output: String(decoding: outputData, as: UTF8.self),
            error: String(decoding: errorData, as: UTF8.self)
        )
    }
    return String(decoding: outputData, as: UTF8.self)
}

private struct TreeConflictCommandError: Error, CustomStringConvertible {
    let executable: String
    let arguments: [String]
    let output: String
    let error: String

    var description: String {
        "Command failed: \(([executable] + arguments).joined(separator: " "))\n\(output)\n\(error)"
    }
}
