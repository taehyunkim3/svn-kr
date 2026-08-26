import Foundation
import Testing
@testable import SVNCore

/// `SVNClient`는 actor지만 actor는 `await` 지점마다 재진입을 허용합니다. 명령 하나가
/// 외부 svn 프로세스를 기다리는 동안 다른 명령이 같은 작업 복사본에 들어옵니다.
/// "actor라서 명령이 직렬화된다"는 설명은 사실이 아니므로 실제 동작을 고정합니다.
@Test func concurrentCommandsOnOneClientOverlapBecauseActorsAreReentrant() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-serialization-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let log = root.appendingPathComponent("command-log")
    let executable = root.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    printf 'start\\n' >> '\(log.path)'
    sleep 0.5
    printf 'end\\n' >> '\(log.path)'
    printf 'https://svn.example.test/project/trunk\\n'
    exit 0
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: root.appendingPathComponent("svn-config").path
    )

    async let first = client.workingCopyRepositoryURL(at: root.path)
    async let second = client.workingCopyRepositoryURL(at: root.path)
    _ = try await (first, second)

    let entries = try String(contentsOf: log, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(entries.count == 4)
    // 직렬화된다면 start,end,start,end 순서여야 한다. 실제로는 두 프로세스가 겹친다.
    #expect(entries.prefix(2) == ["start", "start"])
}
