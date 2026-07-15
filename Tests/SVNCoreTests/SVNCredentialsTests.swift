import Foundation
import Testing
@testable import SVNCore

@Test func sendsPasswordThroughStandardInputNotArguments() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-credentials-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    IFS= read -r supplied_password
    printf 'args=%s\\n' "$*"
    printf 'stdin=%s\\n' "$supplied_password"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(executablePath: executable.path)
    let result = try await client.checkout(
        repositoryURL: "https://example.test/svn/project",
        destinationPath: directory.appendingPathComponent("checkout").path,
        credentials: SVNCredentials(username: "folder-user", password: "keychain-secret")
    )

    #expect(result.contains("--username folder-user"))
    #expect(result.contains("--password-from-stdin"))
    #expect(result.contains("stdin=keychain-secret"))
    let argumentsLine = result.split(separator: "\n").first.map(String.init) ?? ""
    #expect(!argumentsLine.contains("keychain-secret"))
}
