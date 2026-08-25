import Foundation
import Testing
@testable import SVNCore

/// SVN은 `-m` 메시지가 존재하는 경로 이름과 같으면 `-F`를 의도한 실수로 보고
/// `E205005`로 거부합니다. 이 앱의 메시지는 항상 화면 입력값이므로 그 검사를 끕니다.
@Test func commitAcceptsLogMessageThatLooksLikePathname() async throws {
    let fixture = try LogMessagePathnameFixture()
    defer { fixture.remove() }

    let addedName = "test.txt"
    try Data("new\n".utf8).write(to: fixture.workingCopy.appendingPathComponent(addedName))
    _ = try fixture.runSVN(["add", fixture.workingCopy.appendingPathComponent(addedName).path])

    // 메시지가 방금 추가한 파일 이름과 같아도 커밋이 성공해야 합니다.
    _ = try await fixture.client.commit(
        at: fixture.workingCopy.path,
        paths: [addedName],
        message: addedName
    )

    #expect(try fixture.repositoryEntries().contains(addedName))
}

@Test func lockAcceptsCommentThatLooksLikePathname() async throws {
    let fixture = try LogMessagePathnameFixture()
    defer { fixture.remove() }

    _ = try await fixture.client.lock(
        at: fixture.workingCopy.path,
        relativePath: fixture.existingName,
        comment: fixture.existingName
    )

    let information = try fixture.runSVN([
        "info", fixture.workingCopy.appendingPathComponent(fixture.existingName).path,
    ])
    #expect(information.contains("Lock Comment"))
}

private struct LogMessagePathnameFixture {
    let root: URL
    let workingCopy: URL
    let existingName = "base.txt"
    let client: SVNClient
    let repositoryURL: String
    private let svnPath: String

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("svn-log-message-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let importDirectory = root.appendingPathComponent("import", isDirectory: true)
        workingCopy = root.appendingPathComponent("wc", isDirectory: true)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )

        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        try Data("base\n".utf8).write(to: importDirectory.appendingPathComponent(existingName))
        _ = try Self.run(svnadminPath, ["create", repository.path])
        repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try Self.run(svnPath, ["import", importDirectory.path, repositoryURL, "-m", "initial"])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path])
    }

    func runSVN(_ arguments: [String]) throws -> String {
        try Self.run(svnPath, arguments)
    }

    /// 작업 복사본 경로로 `svn list`를 하면 그 경로의 BASE 리비전을 보므로
    /// 부분 커밋 직후에는 새 파일이 보이지 않습니다. 저장소 URL을 직접 조회합니다.
    func repositoryEntries() throws -> [String] {
        try runSVN(["list", repositoryURL])
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "LogMessagePathnameFixture",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return output
    }
}
