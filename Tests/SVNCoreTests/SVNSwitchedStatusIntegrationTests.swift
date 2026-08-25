import Foundation
import Testing
@testable import SVNCore

@Test func realSVNParsesSwitchedNormalDirectory() throws {
    let fileManager = FileManager.default
    let svnPath = try #require(switchedStatusExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(switchedStatusExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = fileManager.temporaryDirectory
        .appendingPathComponent("svn-switched-status-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("working-copy", isDirectory: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runSwitchedStatusCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(
        fileURLWithPath: repository.path,
        isDirectory: true
    ).absoluteString
    _ = try runSwitchedStatusCommand(svnPath, ["mkdir", repositoryURL + "trunk", "-m", "trunk"])
    _ = try runSwitchedStatusCommand(
        svnPath,
        ["mkdir", repositoryURL + "trunk/section", "-m", "section"]
    )
    _ = try runSwitchedStatusCommand(
        svnPath,
        ["mkdir", repositoryURL + "branches", "-m", "branches"]
    )
    _ = try runSwitchedStatusCommand(
        svnPath,
        [
            "copy",
            repositoryURL + "trunk/section",
            repositoryURL + "branches/alternate",
            "-m",
            "branch",
        ]
    )
    _ = try runSwitchedStatusCommand(
        svnPath,
        ["checkout", repositoryURL + "trunk", workingCopy.path]
    )
    _ = try runSwitchedStatusCommand(
        svnPath,
        [
            "switch",
            repositoryURL + "branches/alternate",
            workingCopy.appendingPathComponent("section").path,
        ]
    )

    let statusXML = try runSwitchedStatusCommand(
        svnPath,
        ["status", "--xml", workingCopy.path]
    )
    let entries = try SVNXMLParser.statuses(from: Data(statusXML.utf8))
    let switchedEntry = entries.first { $0.isSwitched }
    let entry = try #require(switchedEntry)

    #expect(statusXML.contains("switched=\"true\""))
    #expect(entry.path.hasSuffix("section"))
    #expect(entry.item.rawValue == "normal")
    #expect(entry.isSelectableForCommit)
}

private func switchedStatusExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runSwitchedStatusCommand(
    _ executable: String,
    _ arguments: [String]
) throws -> String {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: outputData, as: UTF8.self)
    let error = String(decoding: errorData, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw SwitchedStatusCommandError(
            command: ([executable] + arguments).joined(separator: " "),
            output: output + error
        )
    }
    return output
}

private struct SwitchedStatusCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String

    var description: String { "\(command): \(output)" }
}
