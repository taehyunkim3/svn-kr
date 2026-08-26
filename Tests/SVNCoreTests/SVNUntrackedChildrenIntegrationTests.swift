import Foundation
import Testing
@testable import SVNCore

@Test func realSVNPartialAdditionDoesNotIncludeUnselectedSiblings() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(untrackedChildrenExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(untrackedChildrenExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-untracked-children-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("working-copy", isDirectory: true)
    defer {
        do {
            try fileManager.removeItem(at: fixture)
        } catch {
            print("warning: untracked children fixture cleanup failed: \(error)")
        }
    }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runUntrackedChildrenCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runUntrackedChildrenCommand(svnPath, ["mkdir", repositoryURL + "trunk", "-m", "initial"])
    _ = try runUntrackedChildrenCommand(svnPath, ["checkout", repositoryURL + "trunk", workingCopy.path])
    _ = try runUntrackedChildrenCommand(svnPath, [
        "propset", "svn:global-ignores", "*.log", workingCopy.path,
    ])
    _ = try runUntrackedChildrenCommand(svnPath, ["commit", workingCopy.path, "-m", "ignore rule"])

    let directoryName = "신규 자료"
    let directory = workingCopy.appendingPathComponent(directoryName, isDirectory: true)
    let nestedDirectory = directory.appendingPathComponent("하위 폴더", isDirectory: true)
    let selectedFile = directory.appendingPathComponent("선택 문서.txt")
    try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data("selected".utf8).write(to: selectedFile)
    try Data("sibling".utf8).write(to: directory.appendingPathComponent("형제 문서.txt"))
    try Data("ignored".utf8).write(to: directory.appendingPathComponent("제외 문서.log"))
    try Data("nested".utf8).write(to: nestedDirectory.appendingPathComponent("깊은 문서.txt"))

    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let initialChildren = try await client.untrackedChildren(
        at: workingCopy.path,
        directory: directoryName
    )
    let selectedPath = try #require(initialChildren.first {
        $0.path.hasSuffix("선택 문서.txt")
    }?.path)
    _ = try runUntrackedChildrenCommand(svnPath, [
        "add", "--parents", selectedFile.path,
    ])
    let statusAfterAdd = try runUntrackedChildrenCommand(svnPath, [
        "status", "--no-ignore", "--depth", "infinity", directory.path,
    ])
    #expect(statusAfterAdd.contains("A       \(directory.path)/선택 문서.txt"))
    #expect(statusAfterAdd.contains("?       \(directory.path)/형제 문서.txt"))
    #expect(statusAfterAdd.contains("I       \(directory.path)/제외 문서.log"))
    #expect(statusAfterAdd.contains("?       \(nestedDirectory.path)"))

    _ = try runUntrackedChildrenCommand(svnPath, [
        "commit", directory.path, selectedFile.path,
        "-m", "selected file",
    ])
    let repositoryPaths = try runUntrackedChildrenCommand(svnPath, [
        "list", "--recursive", repositoryURL + "trunk",
    ])
    #expect(repositoryPaths.contains("\(directoryName)/\n"))
    #expect(repositoryPaths.contains("\(selectedPath)\n"))
    #expect(!repositoryPaths.contains("형제 문서.txt"))
    #expect(!repositoryPaths.contains("제외 문서.log"))
    #expect(!repositoryPaths.contains("하위 폴더"))

    let localStatus = try runUntrackedChildrenCommand(svnPath, [
        "status", "--no-ignore", "--depth", "infinity", directory.path,
    ])
    #expect(localStatus.contains("?       \(directory.path)/형제 문서.txt"))
    #expect(localStatus.contains("I       \(directory.path)/제외 문서.log"))
    #expect(localStatus.contains("?       \(nestedDirectory.path)"))

    let ignoreRules = try await client.ignoreRules(at: workingCopy.path)
    #expect(ignoreRules.map(\.pattern) == ["*.log"])
    #expect(ignoreRules.map(\.propertyKind) == [.global])
    let children = try await client.untrackedChildren(
        at: workingCopy.path,
        directory: directoryName
    )
    #expect(children.count == 4)
    #expect(children.filter(\.isDirectory).map(\.path) == ["\(directoryName)/하위 폴더"])
    #expect(children.filter(\.isIgnored).map(\.path) == ["\(directoryName)/제외 문서.log"])
    #expect(children.contains { $0.path == selectedPath })
    #expect(!children.contains { $0.path.contains("깊은 문서.txt") })
}

private func untrackedChildrenExecutable(at candidates: [String]) -> String? {
    candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

@discardableResult
private func runUntrackedChildrenCommand(_ executablePath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw SVNUntrackedChildrenIntegrationError(
            command: ([executablePath] + arguments).joined(separator: " "),
            output: text
        )
    }
    return text
}

private struct SVNUntrackedChildrenIntegrationError: Error {
    let command: String
    let output: String
}
