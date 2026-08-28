import Darwin
import Foundation
import Testing
@testable import SVNCore

@Test func realSVNUntrackPreservesLocalFileAndSchedulesRepositoryDeletion() async throws {
    let fixture = try UntrackFixture()
    defer { fixture.remove() }
    let relativePath = "Documents/report.txt"
    let contents = Data("local changes".utf8)
    try fixture.write(contents, relativePath: relativePath)
    try fixture.addAndCommit()
    try fixture.write(contents + Data(" retained".utf8), relativePath: relativePath)

    try await fixture.client.scheduleLocalPreservingDeletion(
        at: fixture.workingCopy.path,
        relativePath: relativePath
    )

    let localURL = fixture.workingCopy.appendingPathComponent(relativePath)
    #expect(try Data(contentsOf: localURL) == contents + Data(" retained".utf8))
    #expect(try await fixture.client.status(at: fixture.workingCopy.path).contains {
        $0.path == relativePath && $0.item == .deleted
    })
}

@Test func realSVNUntrackPreservesDirectoryIncludingUnversionedDescendants() async throws {
    let fixture = try UntrackFixture()
    defer { fixture.remove() }
    try fixture.write(Data("tracked".utf8), relativePath: "generated/tracked.txt")
    try fixture.addAndCommit()
    try fixture.write(Data("local".utf8), relativePath: "generated/local.txt")

    try await fixture.client.scheduleLocalPreservingDeletion(
        at: fixture.workingCopy.path,
        relativePath: "generated"
    )

    #expect(FileManager.default.fileExists(
        atPath: fixture.workingCopy.appendingPathComponent("generated/tracked.txt").path
    ))
    #expect(FileManager.default.fileExists(
        atPath: fixture.workingCopy.appendingPathComponent("generated/local.txt").path
    ))
    let statuses = try await fixture.client.status(at: fixture.workingCopy.path)
    #expect(statuses.contains { $0.path == "generated" && $0.item == .deleted })
    #expect(statuses.contains { $0.path == "generated/local.txt" && $0.item == .unversioned })
}

@Test func realSVNUntrackPreservesScheduledAdditionAsUnversioned() async throws {
    let fixture = try UntrackFixture()
    defer { fixture.remove() }
    let relativePath = "new-report.txt"
    try fixture.write(Data("new".utf8), relativePath: relativePath)
    _ = try run(
        fixture.svnPath,
        ["add", fixture.workingCopy.appendingPathComponent(relativePath).path],
        at: fixture.root
    )

    try await fixture.client.scheduleLocalPreservingDeletion(
        at: fixture.workingCopy.path,
        relativePath: relativePath
    )

    #expect(FileManager.default.fileExists(
        atPath: fixture.workingCopy.appendingPathComponent(relativePath).path
    ))
    #expect(try await fixture.client.status(at: fixture.workingCopy.path).contains {
        $0.path == relativePath && $0.item == .unversioned
    })
}

private struct UntrackFixture {
    let root: URL
    let repositoryURL: String
    let workingCopy: URL
    let svnPath: String
    let client: SVNClient

    init() throws {
        svnPath = try #require(firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("svn-untrack-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("wc", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try run(svnadminPath, ["create", repository.path], at: root)
        repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try run(svnPath, ["checkout", repositoryURL, workingCopy.path], at: root)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("config", isDirectory: true).path
        )
    }

    func write(_ data: Data, relativePath: String) throws {
        let url = workingCopy.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    func addAndCommit() throws {
        _ = try run(svnPath, ["add", "--force", workingCopy.path], at: root)
        _ = try run(svnPath, ["commit", workingCopy.path, "-m", "seed"], at: root)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func firstExecutable(at paths: [String]) -> String? {
    paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

@discardableResult
private func run(_ executable: String, _ arguments: [String], at directory: URL) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw SVNError.commandFailed(
            command: arguments.first ?? executable,
            message: String(decoding: errorData, as: UTF8.self)
        )
    }
    return String(decoding: outputData, as: UTF8.self)
}
