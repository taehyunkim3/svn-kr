import Foundation
import Testing
@testable import SVNCore

@Test func repositoryListXMLIncludesFileAndDirectoryMetadata() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <lists>
    <list path="https://svn.example.com/office/trunk">
    <entry kind="file">
    <name>2026년 &amp; 계획.xlsx</name>
    <size>2048</size>
    <commit revision="42">
    <author>kim.office</author>
    <date>2026-08-25T06:08:17.682246Z</date>
    </commit>
    </entry>
    <entry kind="dir">
    <name>빈 폴더</name>
    <commit revision="41">
    <author>lee.office</author>
    <date>2026-08-24T03:04:05.000000Z</date>
    </commit>
    </entry>
    </list>
    </lists>
    """

    let entries = try SVNXMLParser.repositoryEntries(from: Data(xml.utf8))

    #expect(entries.count == 2)
    #expect(entries[0].name == "2026년 & 계획.xlsx")
    #expect(entries[0].kind == .file)
    #expect(entries[0].size == 2_048)
    #expect(entries[0].lastChangedRevision == "42")
    #expect(entries[0].lastChangedAuthor == "kim.office")
    #expect(entries[0].lastChangedDate != nil)
    #expect(entries[1].name == "빈 폴더")
    #expect(entries[1].kind == .directory)
    #expect(entries[1].size == nil)
    #expect(entries[1].lastChangedRevision == "41")
}

@Test func realSVNRepositoryListReadsMetadataAtRequestedRevision() async throws {
    let fixture = try RepositoryListFixture()
    defer { fixture.remove() }

    let currentEntries = try await fixture.client.repositoryEntries(at: fixture.trunkURL)
    let historicalEntries = try await fixture.client.repositoryEntries(
        at: fixture.trunkURL,
        revision: fixture.initialFileRevision
    )

    let currentFile = try #require(currentEntries.first { $0.name == fixture.fileName })
    let historicalFile = try #require(historicalEntries.first { $0.name == fixture.fileName })
    let directory = try #require(currentEntries.first { $0.name == fixture.directoryName })

    #expect(currentFile.kind == .file)
    #expect(currentFile.size == Int64(fixture.currentContents.count))
    #expect(currentFile.lastChangedRevision == fixture.currentFileRevision)
    #expect(currentFile.lastChangedAuthor == fixture.fileAuthor)
    #expect(currentFile.lastChangedDate != nil)
    #expect(historicalFile.size == Int64(fixture.initialContents.count))
    #expect(historicalFile.lastChangedRevision == fixture.initialFileRevision)
    #expect(directory.kind == .directory)
    #expect(directory.size == nil)
    #expect(directory.lastChangedRevision == fixture.directoryRevision)
    #expect(directory.lastChangedAuthor == fixture.directoryAuthor)
}

private struct RepositoryListFixture {
    let root: URL
    let repository: URL
    let workingCopy: URL
    let trunkURL: String
    let svnPath: String
    let client: SVNClient
    let fileName = "업무 계획.txt"
    let directoryName = "빈 폴더"
    let directoryAuthor = "office.admin"
    let fileAuthor = "office.user"
    let initialContents = Data("초안".utf8)
    let currentContents = Data("확정된 업무 계획".utf8)
    let directoryRevision: String
    let initialFileRevision: String
    let currentFileRevision: String

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(repositoryListExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(repositoryListExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-repository-list-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try runRepositoryListCommand(svnadminPath, ["create", repository.path])
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        trunkURL = repositoryURL + "trunk"
        _ = try runRepositoryListCommand(
            svnPath,
            [
                "mkdir", trunkURL, trunkURL + "/" + directoryName,
                "--username", directoryAuthor, "--no-auth-cache", "-m", "목록 fixture 생성",
            ]
        )
        directoryRevision = try Self.revision(at: trunkURL, svnPath: svnPath)
        _ = try runRepositoryListCommand(svnPath, ["checkout", trunkURL, workingCopy.path])

        let fileURL = workingCopy.appendingPathComponent(fileName, isDirectory: false)
        try initialContents.write(to: fileURL)
        _ = try runRepositoryListCommand(svnPath, ["add", fileURL.path])
        _ = try runRepositoryListCommand(
            svnPath,
            [
                "commit", fileURL.path, "--username", fileAuthor, "--no-auth-cache",
                "-m", "초안 추가",
            ]
        )
        initialFileRevision = try Self.revision(at: trunkURL, svnPath: svnPath)

        try currentContents.write(to: fileURL)
        _ = try runRepositoryListCommand(
            svnPath,
            [
                "commit", fileURL.path, "--username", fileAuthor, "--no-auth-cache",
                "-m", "계획 확정",
            ]
        )
        currentFileRevision = try Self.revision(at: trunkURL, svnPath: svnPath)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func revision(at repositoryURL: String, svnPath: String) throws -> String {
        try runRepositoryListCommand(
            svnPath,
            ["info", "--show-item", "revision", repositoryURL]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func repositoryListExecutable(at candidates: [String]) -> String? {
    candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

@discardableResult
private func runRepositoryListCommand(
    _ executable: String,
    _ arguments: [String]
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw SVNError.commandFailed(command: executable, message: stderr)
    }
    return stdout
}
