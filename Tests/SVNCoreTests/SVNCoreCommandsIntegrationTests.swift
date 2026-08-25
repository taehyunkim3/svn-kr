import Foundation
import Testing
@testable import SVNCore

@Test func realSVNReadsAndExportsHistoricalBinaryBytes() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    let original = Data([0x00, 0x50, 0x4B, 0x03, 0x04, 0xFF, 0x0A, 0x80])
    let changed = Data([0x48, 0x57, 0x50, 0x00, 0xFE])
    try fixture.write(original, relativePath: "document.xlsx")
    try fixture.write(original, relativePath: "archive/document.hwp")
    try fixture.addAndCommit(message: "원본")
    try fixture.write(changed, relativePath: "document.xlsx")
    try fixture.write(changed, relativePath: "archive/document.hwp")
    try fixture.commit(message: "변경")

    let contents = try await fixture.client.fileContents(
        at: fixture.workingCopy.path,
        relativePath: "document.xlsx",
        revision: "2"
    )
    #expect(contents == original)

    let exportedFile = fixture.root.appendingPathComponent("exported.xlsx")
    _ = try await fixture.client.export(
        at: fixture.workingCopy.path,
        relativePath: "document.xlsx",
        revision: "2",
        destinationPath: exportedFile.path
    )
    #expect(try Data(contentsOf: exportedFile) == original)

    let exportedDirectory = fixture.root.appendingPathComponent("exported-directory")
    _ = try await fixture.client.export(
        at: fixture.workingCopy.path,
        relativePath: "archive",
        revision: "2",
        destinationPath: exportedDirectory.path
    )
    #expect(try Data(contentsOf: exportedDirectory.appendingPathComponent("document.hwp")) == original)
}

@Test func realSVNMoveAndCopyPreserveHistory() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    try fixture.write(Data("history".utf8), relativePath: "original.hwp")
    try fixture.addAndCommit(message: "원본")

    _ = try await fixture.client.move(
        at: fixture.workingCopy.path,
        sourceRelativePath: "original.hwp",
        destinationRelativePath: "moved.hwp"
    )
    _ = try await fixture.client.copy(
        at: fixture.workingCopy.path,
        sourceRelativePath: "moved.hwp",
        destinationRelativePath: "copied.hwp"
    )
    try fixture.commit(message: "이동과 복사")

    let movedLog = try fixture.runSVN(["log", "--verbose", "moved.hwp"], at: fixture.workingCopy)
    let copiedLog = try fixture.runSVN(["log", "--verbose", "copied.hwp"], at: fixture.workingCopy)
    #expect(movedLog.contains("원본"))
    #expect(copiedLog.contains("원본"))
    #expect(movedLog.contains("from /trunk/original.hwp:2"))
    #expect(copiedLog.contains("from /trunk/original.hwp:2"))
}

@Test func realSVNCopiesRepositoryURLIntoWorkingCopyWithHistory() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    try fixture.write(Data("source".utf8), relativePath: "source.bin")
    try fixture.addAndCommit(message: "source revision")

    _ = try await fixture.client.copy(
        repositoryURL: fixture.repositoryURL + "/source.bin",
        revision: "2",
        to: "url-copy.bin",
        at: fixture.workingCopy.path
    )
    try fixture.commit(message: "URL copy")

    let log = try fixture.runSVN(["log", "--verbose", "url-copy.bin"], at: fixture.workingCopy)
    #expect(log.contains("source revision"))
    #expect(log.contains("from /trunk/source.bin:2"))
}

@Test func realSVNSetsGetsListsAndDeletesBinaryProperty() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    try fixture.write(Data("document".utf8), relativePath: "locked-document.hwp")
    try fixture.addAndCommit(message: "document")
    let binaryValue = Data([0x00, 0xFF, 0x0A, 0x41, 0x0D, 0x42])

    _ = try await fixture.client.setProperty(
        named: "office:metadata",
        value: binaryValue,
        at: fixture.workingCopy.path,
        relativePath: "locked-document.hwp"
    )
    _ = try await fixture.client.setProperty(
        named: "svn:needs-lock",
        value: Data("*".utf8),
        at: fixture.workingCopy.path,
        relativePath: "locked-document.hwp"
    )
    let value = try await fixture.client.propertyValue(
        named: "office:metadata",
        at: fixture.workingCopy.path,
        relativePath: "locked-document.hwp"
    )
    let properties = try await fixture.client.properties(
        at: fixture.workingCopy.path,
        relativePath: "locked-document.hwp"
    )
    #expect(value == binaryValue)
    #expect(properties.first { $0.name == "office:metadata" }?.value == binaryValue)
    #expect(properties.first { $0.name == "svn:needs-lock" }?.value == Data("*".utf8))

    _ = try await fixture.client.deleteProperty(
        named: "office:metadata",
        at: fixture.workingCopy.path,
        relativePath: "locked-document.hwp"
    )
    let remaining = try await fixture.client.properties(
        at: fixture.workingCopy.path,
        relativePath: "locked-document.hwp"
    )
    #expect(!remaining.contains { $0.name == "office:metadata" })
}

@Test func realSVNLocksAndUnlocksMultipleTargetsAndForcesLockTakeover() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    try fixture.write(Data("a".utf8), relativePath: "a.xlsx")
    try fixture.write(Data("b".utf8), relativePath: "b.hwp")
    try fixture.addAndCommit(message: "lock targets")
    _ = try fixture.runSVN(["update"], at: fixture.secondWorkingCopy)
    let alice = SVNCredentials(username: "alice")
    let bob = SVNCredentials(username: "bob")

    _ = try await fixture.client.lock(
        at: fixture.workingCopy.path,
        relativePaths: ["a.xlsx", "b.hwp"],
        comment: "alice editing",
        credentials: alice
    )
    try fixture.write(
        Data("bob edit".utf8),
        relativePath: "a.xlsx",
        in: fixture.secondWorkingCopy
    )
    do {
        _ = try await fixture.secondClient.commit(
            at: fixture.secondWorkingCopy.path,
            paths: ["a.xlsx"],
            message: "must fail",
            credentials: bob
        )
        Issue.record("Expected another-working-copy lock failure")
    } catch {
        #expect(SVNClient.isLockConflictError(error))
    }
    _ = try await fixture.secondClient.lock(
        at: fixture.secondWorkingCopy.path,
        relativePaths: ["a.xlsx", "b.hwp"],
        comment: "bob takeover",
        force: true,
        credentials: bob
    )
    let firstLock = try await fixture.secondClient.lockInfo(
        at: fixture.secondWorkingCopy.path,
        relativePath: "a.xlsx",
        credentials: bob
    )
    let secondLock = try await fixture.secondClient.lockInfo(
        at: fixture.secondWorkingCopy.path,
        relativePath: "b.hwp",
        credentials: bob
    )
    #expect(firstLock?.owner == "bob")
    #expect(secondLock?.owner == "bob")

    _ = try await fixture.secondClient.unlock(
        at: fixture.secondWorkingCopy.path,
        relativePaths: ["a.xlsx", "b.hwp"],
        credentials: bob
    )
    #expect(try await fixture.secondClient.lockInfo(
        at: fixture.secondWorkingCopy.path,
        relativePath: "a.xlsx",
        credentials: bob
    ) == nil)
}

@Test func realSVNIncomingCommitsContainChangedPathsAndFailWithoutRepository() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    try fixture.write(Data("one".utf8), relativePath: "one.txt")
    try fixture.write(Data("two".utf8), relativePath: "two.txt")
    try fixture.addAndCommit(message: "base")
    _ = try fixture.runSVN(["update"], at: fixture.secondWorkingCopy)
    try fixture.write(Data("one remote".utf8), relativePath: "one.txt", in: fixture.secondWorkingCopy)
    try fixture.write(Data("two remote".utf8), relativePath: "two.txt", in: fixture.secondWorkingCopy)
    try fixture.commit(message: "remote one", workingCopy: fixture.secondWorkingCopy)
    try fixture.write(Data("one again".utf8), relativePath: "one.txt", in: fixture.secondWorkingCopy)
    try fixture.commit(message: "remote two", workingCopy: fixture.secondWorkingCopy)

    let workingCopyRevision = try await fixture.client.workingCopyRevision(at: fixture.workingCopy.path)
    let commits = try await fixture.client.incomingCommits(at: fixture.workingCopy.path)
    #expect(workingCopyRevision == SVNWorkingCopyRevision(minimum: "1", maximum: "2"))
    #expect(commits.map(\.revision) == ["2", "3", "4"])
    #expect(commits[0].changedPaths.map(\.path).contains("/trunk/one.txt"))
    #expect(commits[0].changedPaths.map(\.path).contains("/trunk/two.txt"))
    #expect(commits[1].changedPaths.map(\.path).contains("/trunk/one.txt"))
    #expect(commits[1].changedPaths.map(\.path).contains("/trunk/two.txt"))
    #expect(commits[2].changedPaths.map(\.path) == ["/trunk/one.txt"])

    let movedRepository = fixture.root.appendingPathComponent("repository-offline", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.repository, to: movedRepository)
    do {
        _ = try await fixture.client.incomingCommits(at: fixture.workingCopy.path)
        Issue.record("Expected repository connection failure")
    } catch {
        #expect(SVNClient.isRepositoryConnectionError(error))
    }
}

@Test func realSVNRelocateRestoresRemoteAccessAndPreservesLocalChanges() async throws {
    let fixture = try CoreCommandsFixture()
    defer { fixture.remove() }
    try fixture.write(Data("base".utf8), relativePath: "local-change.txt")
    try fixture.addAndCommit(message: "base")
    try fixture.write(Data("uncommitted".utf8), relativePath: "local-change.txt")
    let movedRepository = fixture.root.appendingPathComponent("repository-moved", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.repository, to: movedRepository)

    do {
        _ = try await fixture.client.update(at: fixture.workingCopy.path)
        Issue.record("Expected update failure before relocate")
    } catch {
        #expect(SVNClient.isRepositoryConnectionError(error))
    }
    let newRepositoryURL = movedRepository.absoluteString + "trunk"
    _ = try await fixture.client.relocate(
        at: fixture.workingCopy.path,
        fromRepositoryURL: fixture.repositoryURL,
        toRepositoryURL: newRepositoryURL
    )
    #expect(try await fixture.client.workingCopyRepositoryURL(at: fixture.workingCopy.path) == newRepositoryURL)
    _ = try await fixture.client.update(at: fixture.workingCopy.path)
    #expect(try Data(contentsOf: fixture.workingCopy.appendingPathComponent("local-change.txt")) == Data("uncommitted".utf8))
    #expect(try fixture.runSVN(["status"], at: fixture.workingCopy).contains("M       local-change.txt"))
}

private final class CoreCommandsFixture {
    let root: URL
    let repository: URL
    let workingCopy: URL
    let secondWorkingCopy: URL
    let repositoryURL: String
    let svnPath: String
    let client: SVNClient
    let secondClient: SVNClient

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(coreCommandsExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(coreCommandsExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-core-commands-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        secondWorkingCopy = root.appendingPathComponent("second-working-copy", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try runCoreCommandsProcess(svnadminPath, ["create", repository.path])
        repositoryURL = repository.absoluteString + "trunk"
        _ = try runCoreCommandsProcess(svnPath, ["mkdir", repositoryURL, "-m", "trunk"])
        _ = try runCoreCommandsProcess(svnPath, ["checkout", repositoryURL, workingCopy.path])
        _ = try runCoreCommandsProcess(svnPath, ["checkout", repositoryURL, secondWorkingCopy.path])
        let configPath = root.appendingPathComponent("svn-config", isDirectory: true).path
        client = SVNClient(executablePath: svnPath, configDirectoryPath: configPath)
        secondClient = SVNClient(executablePath: svnPath, configDirectoryPath: configPath)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ data: Data, relativePath: String, in root: URL? = nil) throws {
        let root = root ?? workingCopy
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    func addAndCommit(message: String) throws {
        _ = try runSVN(["add", "--force", "."], at: workingCopy)
        try commit(message: message)
    }

    func commit(message: String, workingCopy: URL? = nil) throws {
        _ = try runSVN(["commit", "-m", message], at: workingCopy ?? self.workingCopy)
    }

    @discardableResult
    func runSVN(_ arguments: [String], at workingCopy: URL) throws -> String {
        try runCoreCommandsProcess(svnPath, arguments, currentDirectory: workingCopy)
    }
}

private func coreCommandsExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runCoreCommandsProcess(
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
        throw CoreCommandsProcessError(
            command: ([executable] + arguments).joined(separator: " "),
            output: String(decoding: outputData, as: UTF8.self),
            error: String(decoding: errorData, as: UTF8.self)
        )
    }
    return String(decoding: outputData, as: UTF8.self)
}

private struct CoreCommandsProcessError: Error, CustomStringConvertible {
    let command: String
    let output: String
    let error: String

    var description: String { "\(command)\n\(output)\n\(error)" }
}
