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
    let untrackedDirectoryPath = try #require(try await client.status(at: workingCopy.path).first {
        $0.item == .unversioned && $0.path.hasSuffix(directoryName)
    }?.path)
    let initialChildren = try await client.untrackedChildren(
        at: workingCopy.path,
        directory: untrackedDirectoryPath
    )
    let selectedPath = try #require(initialChildren.first {
        $0.path.hasSuffix("선택 문서.txt")
    }?.path)
    _ = try await client.commit(
        at: workingCopy.path,
        paths: [selectedPath],
        message: "selected file"
    )
    let repositoryPaths = try runUntrackedChildrenCommand(svnPath, [
        "list", "--recursive", repositoryURL + "trunk",
    ])
    #expect(repositoryPaths.contains("\(directoryName)/\n"))
    #expect(repositoryPaths.contains("\(selectedPath)\n"))
    #expect(!repositoryPaths.contains("형제 문서.txt"))
    #expect(!repositoryPaths.contains("제외 문서.log"))
    #expect(!repositoryPaths.contains("하위 폴더"))

    let localStatus = try runUntrackedChildrenCommand(svnPath, [
        "status", "--no-ignore", "--depth", "infinity", workingCopy.path,
    ])
    #expect(localStatus.contains("?       \(directory.path)/형제 문서.txt"))
    #expect(localStatus.contains("I       \(directory.path)/제외 문서.log"))
    #expect(localStatus.contains("?       \(nestedDirectory.path)"))

    let ignoreRules = try await client.ignoreRules(at: workingCopy.path)
    #expect(ignoreRules.map(\.pattern) == ["*.log"])
    #expect(ignoreRules.map(\.propertyKind) == [.global])
    let children = try await client.untrackedChildren(
        at: workingCopy.path,
        directory: untrackedDirectoryPath
    )
    #expect(children.count == 4)
    #expect(children.filter(\.isDirectory).map(\.path) == ["\(directoryName)/하위 폴더"])
    #expect(children.filter(\.isIgnored).map(\.path) == ["\(directoryName)/제외 문서.log"])
    #expect(children.contains { $0.path == selectedPath })
    #expect(!children.contains { $0.path.contains("깊은 문서.txt") })
}

@Test func realSVNCommitSelectedChildLeavesPreexistingAddedSiblingScheduled() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(untrackedChildrenExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(untrackedChildrenExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-selected-child-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("working-copy", isDirectory: true)
    defer { removeUntrackedChildrenFixture(fixture, fileManager: fileManager) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runUntrackedChildrenCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runUntrackedChildrenCommand(svnPath, ["mkdir", repositoryURL + "trunk", "-m", "initial"])
    _ = try runUntrackedChildrenCommand(svnPath, ["checkout", repositoryURL + "trunk", workingCopy.path])

    let directory = workingCopy.appendingPathComponent("부분 폴더", isDirectory: true)
    let selectedFile = directory.appendingPathComponent("선택 파일.txt")
    let scheduledSibling = directory.appendingPathComponent("예약 형제.txt")
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("selected".utf8).write(to: selectedFile)
    try Data("sibling".utf8).write(to: scheduledSibling)
    _ = try runUntrackedChildrenCommand(svnPath, ["add", "--parents", scheduledSibling.path])

    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let parentPath = try #require(try await client.status(at: workingCopy.path).first {
        $0.item == .added && $0.path.hasSuffix("부분 폴더")
    }?.path)
    let selectedPath = try #require(try await client.untrackedChildren(
        at: workingCopy.path,
        directory: parentPath
    ).first { $0.path.hasSuffix("선택 파일.txt") }?.path)
    _ = try await client.commit(
        at: workingCopy.path,
        paths: [selectedPath],
        message: "selected child"
    )

    let repositoryPaths = try runUntrackedChildrenCommand(svnPath, [
        "list", "--recursive", repositoryURL + "trunk",
    ])
    #expect(repositoryPaths.contains("부분 폴더/선택 파일.txt"))
    #expect(!repositoryPaths.contains("예약 형제.txt"))
    let localStatus = try runUntrackedChildrenCommand(svnPath, ["status", workingCopy.path])
    #expect(localStatus.contains("A       \(scheduledSibling.path)"))
}

@Test func realSVNCommitSelectedUntrackedDirectoryKeepsRecursiveBehavior() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(untrackedChildrenExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(untrackedChildrenExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-selected-directory-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("working-copy", isDirectory: true)
    defer { removeUntrackedChildrenFixture(fixture, fileManager: fileManager) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runUntrackedChildrenCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runUntrackedChildrenCommand(svnPath, ["mkdir", repositoryURL + "trunk", "-m", "initial"])
    _ = try runUntrackedChildrenCommand(svnPath, ["checkout", repositoryURL + "trunk", workingCopy.path])

    let directoryName = "전체 폴더"
    let directory = workingCopy.appendingPathComponent(directoryName, isDirectory: true)
    let nestedDirectory = directory.appendingPathComponent("하위", isDirectory: true)
    try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data("first".utf8).write(to: directory.appendingPathComponent("첫째.txt"))
    try Data("second".utf8).write(to: directory.appendingPathComponent("둘째.txt"))
    try Data("nested".utf8).write(to: nestedDirectory.appendingPathComponent("깊은.txt"))

    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let selectedDirectoryPath = try #require(try await client.status(at: workingCopy.path).first {
        $0.item == .unversioned && $0.path.hasSuffix(directoryName)
    }?.path)
    _ = try await client.commit(
        at: workingCopy.path,
        paths: [selectedDirectoryPath],
        message: "selected directory"
    )

    let repositoryPaths = try runUntrackedChildrenCommand(svnPath, [
        "list", "--recursive", repositoryURL + "trunk",
    ])
    #expect(repositoryPaths.contains("전체 폴더/첫째.txt"))
    #expect(repositoryPaths.contains("전체 폴더/둘째.txt"))
    #expect(repositoryPaths.contains("전체 폴더/하위/깊은.txt"))
    #expect(try runUntrackedChildrenCommand(svnPath, ["status", workingCopy.path]).isEmpty)
}

private func untrackedChildrenExecutable(at candidates: [String]) -> String? {
    candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func removeUntrackedChildrenFixture(_ fixture: URL, fileManager: FileManager) {
    do {
        try fileManager.removeItem(at: fixture)
    } catch {
        print("warning: untracked children fixture cleanup failed: \(error)")
    }
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
