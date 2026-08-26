import Foundation
import Testing
@testable import SVNCore

/// 복구는 손상된 작업 복사본의 BASE 리비전으로 체크아웃해야 합니다. HEAD로 체크아웃하면
/// 그 사이 동료가 올린 커밋이 out-of-date 검사에 걸리지 않고 조용히 덮어써집니다.
@Test func realSVNRecoveryChecksOutSourceBaseRevisionSoLaterCommitStaysOutOfDate() async throws {
    let fixture = try SVNRecoveryIntegrationFixture()
    defer { fixture.remove() }

    let fileName = "보고서.txt"
    let sourceFile = fixture.source.appendingPathComponent(fileName)
    let peerFile = fixture.peer.appendingPathComponent(fileName)

    try Data("r1\n".utf8).write(to: sourceFile)
    _ = try runSVNRecoveryCommand(fixture.svnPath, ["add", fileName], currentDirectory: fixture.source)
    _ = try runSVNRecoveryCommand(fixture.svnPath, ["commit", "-m", "r1"], currentDirectory: fixture.source)
    _ = try runSVNRecoveryCommand(fixture.svnPath, ["update"], currentDirectory: fixture.peer)

    // 동료가 같은 파일을 고쳐 올린다. 손상된 작업 복사본은 update하지 않는다.
    try Data("r1\n동료 추가\n".utf8).write(to: peerFile)
    _ = try runSVNRecoveryCommand(fixture.svnPath, ["commit", "-m", "r2"], currentDirectory: fixture.peer)

    try Data("내 수정\n".utf8).write(to: sourceFile)

    let destination = fixture.root.appendingPathComponent("recovered", isDirectory: true)
    let result = try await fixture.client.recoverWorkingCopy(
        from: fixture.source.path,
        to: destination.path
    )

    #expect(result.snapshot.revision.maximum == "1")

    // 복구 결과에서 곧바로 커밋하면 동료의 r2가 사라진다. out-of-date로 막혀야 한다.
    let commit = runSVNRecoveryCommandResult(
        fixture.svnPath,
        ["commit", "-m", "복구 후 커밋"],
        currentDirectory: destination
    )
    #expect(commit.exitCode != 0)
    #expect(commit.error.contains("E155011") || commit.error.contains("out of date"))

    // 사용자가 직접 update하면 충돌로 보인다.
    _ = runSVNRecoveryCommandResult(fixture.svnPath, ["update"], currentDirectory: destination)
    let status = try await fixture.client.status(at: destination.path)
    #expect(status.contains { $0.path == fileName && $0.item == .conflicted })
}

private struct SVNRecoveryIntegrationFixture {
    let root: URL
    let source: URL
    let peer: URL
    let svnPath: String
    let client: SVNClient

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(svnRecoveryExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(svnRecoveryExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-recovery-integration-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        peer = root.appendingPathComponent("peer", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try runSVNRecoveryCommand(svnadminPath, ["create", repository.path])
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try runSVNRecoveryCommand(svnPath, ["checkout", repositoryURL, source.path])
        _ = try runSVNRecoveryCommand(svnPath, ["checkout", repositoryURL, peer.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func svnRecoveryExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runSVNRecoveryCommand(
    _ executable: String,
    _ arguments: [String],
    currentDirectory: URL? = nil
) throws -> String {
    let result = runSVNRecoveryCommandResult(executable, arguments, currentDirectory: currentDirectory)
    guard result.exitCode == 0 else {
        throw SVNRecoveryCommandError(
            executable: executable,
            arguments: arguments,
            output: result.output,
            error: result.error
        )
    }
    return result.output
}

private func runSVNRecoveryCommandResult(
    _ executable: String,
    _ arguments: [String],
    currentDirectory: URL? = nil
) -> SVNRecoveryCommandResult {
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
    } catch {
        return SVNRecoveryCommandResult(output: "", error: "\(error)", exitCode: -1)
    }
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return SVNRecoveryCommandResult(
        output: String(decoding: outputData, as: UTF8.self),
        error: String(decoding: errorData, as: UTF8.self),
        exitCode: process.terminationStatus
    )
}

private struct SVNRecoveryCommandResult {
    let output: String
    let error: String
    let exitCode: Int32
}

private struct SVNRecoveryCommandError: Error {
    let executable: String
    let arguments: [String]
    let output: String
    let error: String
}
