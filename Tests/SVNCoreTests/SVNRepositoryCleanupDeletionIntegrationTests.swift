import Darwin
import Foundation
import Testing
@testable import SVNCore

@Test func realSVNSchedulesCleanupDeletionAndRemovesFileFromRepository() async throws {
    let fixture = try CleanupDeletionFixture()
    defer { fixture.remove() }
    let keptPath = fixture.workingCopy.path + "/keep.txt"
    let junkPath = fixture.workingCopy.path + "/.DS_Store"
    try writeCleanupFile(Data("keep".utf8), atPath: keptPath)
    try writeCleanupFile(Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31]), atPath: junkPath)
    _ = try runCleanupCommand(fixture.svnPath, ["add", "--force", "--no-ignore", fixture.workingCopy.path])
    _ = try runCleanupCommand(fixture.svnPath, ["commit", fixture.workingCopy.path, "-m", "seed"])

    try await fixture.client.scheduleRepositoryCleanupDeletion(
        at: fixture.workingCopy.path,
        relativePath: ".DS_Store"
    )

    // 예약 직후에는 작업 사본에서 삭제 예약 상태이고 디스크에서도 사라져야 합니다.
    let statuses = try await fixture.client.status(at: fixture.workingCopy.path)
    #expect(statuses.contains { $0.path == ".DS_Store" && $0.item == .deleted })
    #expect(!FileManager.default.fileExists(atPath: junkPath))
    #expect(FileManager.default.fileExists(atPath: keptPath))

    _ = try await fixture.client.commit(
        at: fixture.workingCopy.path,
        paths: [".DS_Store"],
        message: "cleanup"
    )
    let remaining = try runCleanupCommand(fixture.svnPath, ["list", fixture.repositoryURL])
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    #expect(remaining == ["keep.txt"])
}

@Test func realSVNSchedulesCleanupDeletionForDecomposedKoreanPath() async throws {
    let fixture = try CleanupDeletionFixture()
    defer { fixture.remove() }
    let nfcDirectory = "한글폴더"
    let nfdDirectory = nfcDirectory.decomposedStringWithCanonicalMapping
    try createCleanupDirectory(atPath: fixture.workingCopy.path + "/" + nfdDirectory)
    try writeCleanupFile(
        Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31]),
        atPath: fixture.workingCopy.path + "/" + nfdDirectory + "/.DS_Store"
    )
    _ = try runCleanupCommand(fixture.svnPath, ["add", "--force", "--no-ignore", fixture.workingCopy.path])
    _ = try runCleanupCommand(fixture.svnPath, ["commit", fixture.workingCopy.path, "-m", "seed"])

    // 저장소 원문이 자모 분리 표기인 경로도 예약이 되어야 합니다.
    try await fixture.client.scheduleRepositoryCleanupDeletion(
        at: fixture.workingCopy.path,
        relativePath: nfdDirectory + "/.DS_Store"
    )
    let statuses = try await fixture.client.status(at: fixture.workingCopy.path)
    #expect(statuses.contains {
        Data($0.path.utf8) == Data((nfdDirectory + "/.DS_Store").utf8) && $0.item == .deleted
    })
}

@Test func realSVNCleanupDeletionFailsForUnversionedPath() async throws {
    let fixture = try CleanupDeletionFixture()
    defer { fixture.remove() }
    try writeCleanupFile(Data("keep".utf8), atPath: fixture.workingCopy.path + "/keep.txt")
    _ = try runCleanupCommand(fixture.svnPath, ["add", "--force", "--no-ignore", fixture.workingCopy.path])
    _ = try runCleanupCommand(fixture.svnPath, ["commit", fixture.workingCopy.path, "-m", "seed"])

    await #expect(throws: Error.self) {
        try await fixture.client.scheduleRepositoryCleanupDeletion(
            at: fixture.workingCopy.path,
            relativePath: "없는파일.txt"
        )
    }
}

private struct CleanupDeletionFixture {
    let root: URL
    let workingCopy: URL
    let repositoryURL: String
    let svnPath: String
    let client: SVNClient

    init() throws {
        svnPath = try #require(firstCleanupExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(firstCleanupExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("svn-cleanup-deletion-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("wc", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try runCleanupCommand(svnadminPath, ["create", repository.path])
        repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try runCleanupCommand(svnPath, ["checkout", repositoryURL, workingCopy.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("config", isDirectory: true).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func firstCleanupExecutable(at paths: [String]) -> String? {
    paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func createCleanupDirectory(atPath path: String) throws {
    guard path.withCString({ mkdir($0, S_IRWXU) }) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func writeCleanupFile(_ data: Data, atPath path: String) throws {
    let descriptor = path.withCString {
        Darwin.open($0, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(descriptor) }
    try data.withUnsafeBytes { buffer in
        guard buffer.isEmpty || write(descriptor, buffer.baseAddress, buffer.count) == buffer.count else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

@discardableResult
private func runCleanupCommand(
    _ executablePath: String,
    _ arguments: [String]
) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw POSIXError(.EIO)
    }
    return String(decoding: data, as: UTF8.self)
}
