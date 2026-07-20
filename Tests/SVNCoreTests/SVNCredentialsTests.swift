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

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
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
    #expect(!argumentsLine.contains("--trust-server-cert-failures"))
}

@Test func normalizesCheckoutURLToPrecomposedUnicode() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-url-normalization-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    printf '%s\n' "$*"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let decomposedRepositoryURL = "https://example.test/svn/\u{1112}\u{1161}\u{11AB}\u{1100}\u{116E}\u{11A8}"
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.checkout(
        repositoryURL: decomposedRepositoryURL,
        destinationPath: directory.appendingPathComponent("checkout").path
    )

    #expect(result.contains("https://example.test/svn/%ED%95%9C%EA%B5%AD"))
    #expect(!result.contains("%E1%84%92%E1%85%A1"))
}

@Test func runsCheckoutInsideSelectedDestination() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-checkout-destination-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    : > checkout-marker
    printf 'cwd=%s\n' "$PWD"
    printf 'args=%s\n' "$*"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let destination = directory.appendingPathComponent("checkout", isDirectory: true)
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.checkout(
        repositoryURL: "https://example.test/svn/project",
        destinationPath: destination.path,
        allowUntrustedServerCertificate: true
    )

    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("checkout-marker").path))
    #expect(result.contains("--trust-server-cert-failures=unknown-ca,cn-mismatch"))
    #expect(result.contains("checkout https://example.test/svn/project ."))
}

@Test func requestsRemoteLogFromHeadWithoutUpdatingWorkingCopy() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-remote-log-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"log --xml --verbose --with-all-revprops --revision HEAD:1 --limit 50"*)
        printf '<?xml version="1.0"?><log><logentry revision="42"><author>tester</author><msg>remote</msg></logentry></log>'
        ;;
      *)
        printf 'unexpected arguments: %s\n' "$*" >&2
        exit 1
        ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let entries = try await client.log(at: directory.path)

    #expect(entries.map(\.revision) == ["42"])
}

@Test func requestsRevisionDiffForOnlySelectedRepositoryPath() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-revision-file-diff-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    printf '%s\n' "$*"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.revisionDiff(
        at: directory.path,
        revision: "42",
        repositoryPath: "/trunk/Sources/App.swift",
        workingCopyRepositoryPath: "/trunk",
        pegRevision: "42"
    )

    #expect(result.contains("diff --change 42 -- ^/trunk/Sources/App.swift@42"))
}

@Test func revisionDiffUsesExactWorkingCopyRootAndPreservesNFDFileName() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-revision-unicode-path-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    printf '%s\n' "$*"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let nfdFileName = "테스트.png"
    let result = try await client.revisionDiff(
        at: directory.path,
        revision: "42",
        repositoryPath: "/한글/project/images/\(nfdFileName)",
        workingCopyRepositoryPath: "/%ED%95%9C%EA%B8%80/project",
        pegRevision: "42"
    )

    let resultData = Data(result.utf8)
    #expect(resultData.range(of: Data("^/%ED%95%9C%EA%B8%80/project/images/\(nfdFileName)@42".utf8)) != nil)
    #expect(resultData.range(of: Data("테스트.png".utf8)) == nil)
}

@Test func revisionDiffKeepsRepositoryPathOutsideWorkingCopyRoot() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-revision-outside-root-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    printf '%s\n' "$*"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.revisionDiff(
        at: directory.path,
        revision: "42",
        repositoryPath: "/shared/Old.swift",
        workingCopyRepositoryPath: "/project/trunk",
        pegRevision: "41"
    )

    #expect(result.contains("^/shared/Old.swift@41"))
}

@Test func readsTrimmedWorkingCopyRevision() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-working-copy-revision-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --verbose --xml"*) printf '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="37"/></entry><entry path="file.txt"><wc-status item="normal" revision="41"/></entry></target></status>' ;;
      *) exit 1 ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let revision = try await client.workingCopyRevision(at: directory.path)

    #expect(revision == SVNWorkingCopyRevision(minimum: "37", maximum: "41"))
}

@Test func readsWorkingCopyPathRelativeToRepositoryRoot() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-working-copy-repository-path-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"info --show-item relative-url"*) printf '^/project/trunk/backend\n' ;;
      *) exit 1 ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let repositoryPath = try await client.workingCopyRepositoryPath(at: directory.path)

    #expect(repositoryPath == "/project/trunk/backend")
}

@Test func commitsKoreanMessageWithUTF8Locale() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-korean-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --xml"*)
        printf '<?xml version="1.0"?><status><target path="."><entry path="한글.txt"><wc-status item="modified" revision="1"/></entry></target></status>'
        ;;
      *"commit --message"*)
        printf 'LANG=%s\nLC_ALL=%s\nargs=%s\n' "$LANG" "$LC_ALL" "$*"
        ;;
      *) exit 1 ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.commit(
        at: directory.path,
        paths: ["한글.txt"],
        message: "한글 커밋 메시지"
    )

    #expect(result.contains("LANG=en_US.UTF-8"))
    #expect(result.contains("LC_ALL=en_US.UTF-8"))
    #expect(result.contains("commit --message 한글 커밋 메시지 -- 한글.txt"))
}
