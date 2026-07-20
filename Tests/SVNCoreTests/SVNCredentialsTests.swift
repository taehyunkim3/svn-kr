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

@Test func batchesSelectedCommitTargets() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-batched-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then
        targets=$argument
        expects_targets=0
        continue
      fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|add|delete|commit) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '<?xml version="1.0"?><status><target path="."><entry path="Old"><wc-status item="missing" revision="1"/></entry><entry path="Old/file.txt"><wc-status item="missing" revision="1"/></entry><entry path="Old/nested/file.txt"><wc-status item="missing" revision="1"/></entry><entry path="New"><wc-status item="unversioned"/></entry><entry path="Application/file.swift"><wc-status item="modified" revision="1"/></entry><entry path="App/file.swift"><wc-status item="modified" revision="1"/></entry></target></status>'
      exit 0
    fi
    printf '%s\n' "$command" >> command-log
    if [ -n "$targets" ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        printf '%s:%s\n' "$command" "$target" >> command-log
      done < "$targets"
    fi
    if [ "$command" = commit ]; then
      printf 'committed\n'
    fi
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    _ = try await client.commit(
        at: directory.path,
        paths: [
            "Old", "Old/file.txt", "Old/nested/file.txt",
            "New", "Application/file.swift", "App/file.swift",
        ],
        message: "batch"
    )

    let log = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
    let lines = log.split(whereSeparator: \.isNewline).map(String.init)
    #expect(lines.filter { $0 == "add" }.count == 1)
    #expect(lines.filter { $0 == "delete" }.count == 1)
    #expect(lines.filter { $0 == "commit" }.count == 1)
    #expect(lines.contains("add:New"))
    #expect(lines.contains("delete:Old"))
    #expect(!lines.contains("delete:Old/file.txt"))
    #expect(!lines.contains("delete:Old/nested/file.txt"))
    #expect(lines.contains("commit:App/file.swift"))
    #expect(lines.contains("commit:Application/file.swift"))
    #expect(lines.contains("commit:New"))
    #expect(lines.contains("commit:Old"))
}

@Test func commitMapsDecomposedSelectionToExistingPrecomposedAncestor() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-normalized-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let precomposedDirectory = "구현"
    let decomposedDirectory = precomposedDirectory.decomposedStringWithCanonicalMapping
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then
        targets=$argument
        expects_targets=0
        continue
      fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|add|commit) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(precomposedDirectory)"><wc-status item="normal" revision="1"/></entry><entry path="\(decomposedDirectory)/새 파일.txt"><wc-status item="unversioned"/></entry></target></status>'
      exit 0
    fi
    if [ -n "$targets" ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        printf '%s:%s\n' "$command" "$target" >> command-log
      done < "$targets"
    fi
    [ "$command" = commit ] && printf 'committed\n'
    exit 0
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    _ = try await client.commit(
        at: directory.path,
        paths: ["\(decomposedDirectory)/새 파일.txt"],
        message: "정규화 경로"
    )

    let log = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
    #expect(log.contains("add:\(precomposedDirectory)/새 파일.txt"))
    #expect(log.contains("commit:\(precomposedDirectory)/새 파일.txt"))
    let rawLines = log.split(whereSeparator: \.isNewline).map { Data($0.utf8) }
    #expect(rawLines.contains(Data("add:\(precomposedDirectory)/새 파일.txt".utf8)))
    #expect(!rawLines.contains(Data("add:\(decomposedDirectory)/새 파일.txt".utf8)))
}

@Test func commitRepairsCanonicalAliasesBeforeScheduling() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-commit-alias-repair-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composedRoot = "00 사업관리"
    let nfdRoot = composedRoot.decomposedStringWithCanonicalMapping
    let nfdNewFile = "\(nfdRoot)/새 파일.hwp"
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then
        targets=$argument
        expects_targets=0
        continue
      fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|revert|add|delete|commit) command=$argument ;;
      esac
    done
    printf '%s\n' "$command" >> command-log
    if [ "$command" = status ]; then
      if [ ! -f alias-repaired ]; then
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="missing" revision="-1"/></entry><entry path="\(composedRoot)/기존 파일.hwp"><wc-status item="modified" revision="1"/></entry><entry path="\(nfdNewFile)"><wc-status item="unversioned"/></entry></target></status>'
      else
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)/기존 파일.hwp"><wc-status item="modified" revision="1"/></entry><entry path="\(nfdNewFile)"><wc-status item="unversioned"/></entry></target></status>'
      fi
      exit 0
    fi
    if [ -n "$targets" ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        printf '%s:%s\n' "$command" "$target" >> target-log
      done < "$targets"
    fi
    if [ "$command" = revert ]; then
      : > alias-repaired
      exit 0
    fi
    if [ "$command" = commit ]; then
      printf 'committed\n'
    fi
    exit 0
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    _ = try await client.commit(
        at: directory.path,
        paths: ["\(composedRoot)/기존 파일.hwp", nfdNewFile],
        message: "별칭 복구"
    )

    let commands = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    #expect(commands == ["status", "revert", "status", "add", "commit"])

    let targets = try Data(contentsOf: directory.appendingPathComponent("target-log"))
    #expect(targets.range(of: Data("revert:\(nfdRoot)\n".utf8)) != nil)
    #expect(targets.range(of: Data("add:\(composedRoot)/새 파일.hwp\n".utf8)) != nil)
    #expect(targets.range(of: Data("commit:\(composedRoot)/새 파일.hwp\n".utf8)) != nil)
    #expect(targets.range(of: Data("commit:\(composedRoot)/기존 파일.hwp\n".utf8)) != nil)
    #expect(targets.range(of: Data("add:\(nfdNewFile)\n".utf8)) == nil)
    #expect(targets.range(of: Data("commit:\(nfdNewFile)\n".utf8)) == nil)
}

@Test func commitFailureRevertsOnlySchedulingPerformedByCommit() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-commit-rollback-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then
        targets=$argument
        expects_targets=0
        continue
      fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|add|commit|revert) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="새 파일.txt"><wc-status item="unversioned"/></entry><entry path="기존.txt"><wc-status item="modified" revision="1"/></entry></target></status>'
      exit 0
    fi
    if [ -n "$targets" ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        printf '%s:%s\n' "$command" "$target" >> command-log
      done < "$targets"
    fi
    if [ "$command" = commit ]; then
      printf 'commit failed\n' >&2
      exit 1
    fi
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    await #expect(throws: SVNError.self) {
        _ = try await client.commit(
            at: directory.path,
            paths: ["새 파일.txt", "기존.txt"],
            message: "실패"
        )
    }

    let log = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
    #expect(log.contains("add:새 파일.txt"))
    #expect(log.contains("revert:새 파일.txt"))
    #expect(!log.contains("revert:기존.txt"))
}

@Test func commitRejectsCanonicalPathCollisionBeforeMutation() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-collision-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let precomposed = "구현"
    let decomposed = precomposed.decomposedStringWithCanonicalMapping
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    for argument in "$@"; do
      case "$argument" in
        status|add|delete|commit|revert) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(precomposed)"><wc-status item="normal" revision="1"/></entry><entry path="\(decomposed)"><wc-status item="normal" revision="1"/></entry></target></status>'
      exit 0
    fi
    printf '%s\n' "$command" >> mutation-log
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    do {
        _ = try await client.commit(at: directory.path, paths: [precomposed], message: "충돌")
        Issue.record("경로 충돌 커밋이 거부되어야 합니다.")
    } catch let SVNError.pathNormalizationCollision(paths) {
        #expect(paths == [precomposed])
    } catch {
        Issue.record("예상하지 못한 오류: \(error)")
    }

    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("mutation-log").path))
}

@Test func commitsTwentyThousandPathsThroughTargetsFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-large-targets-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then
        targets=$argument
        expects_targets=0
        continue
      fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|commit) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry></target></status>'
      exit 0
    fi
    count=0
    if [ -n "$targets" ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        count=$((count + 1))
      done < "$targets"
    fi
    printf 'commit-count=1\ntarget-count=%s\n' "$count"
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let paths = (0..<20_000).map {
        "Sources/LongDirectoryNameForArgumentLimit/file-\($0)-한글.swift"
    }
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.commit(at: directory.path, paths: paths, message: "large")

    #expect(result.contains("commit-count=1"))
    #expect(result.contains("target-count=20000"))
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
      *"status --verbose --no-ignore --xml"*)
        printf '<?xml version="1.0"?><status><target path="."><entry path="한글.txt"><wc-status item="modified" revision="1"/></entry></target></status>'
        ;;
      *"commit --message"*)
        targets=
        expects_targets=0
        for argument in "$@"; do
          if [ "$expects_targets" = 1 ]; then
            targets=$argument
            expects_targets=0
            continue
          fi
          if [ "$argument" = --targets ]; then
            expects_targets=1
          fi
        done
        printf 'LANG=%s\nLC_ALL=%s\nargs=%s\n' "$LANG" "$LC_ALL" "$*"
        if [ -n "$targets" ]; then
          while IFS= read -r target || [ -n "$target" ]; do
            printf 'target=%s\n' "$target"
          done < "$targets"
        fi
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
    #expect(result.contains("commit --message 한글 커밋 메시지 --targets"))
    #expect(result.contains("target=한글.txt"))
}

@Test func repairCanonicalAliasesRevertsExactMissingNFDTargetWithoutChangingLocalFiles() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-alias-repair-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composedRoot = "04 구현"
    let nfdRoot = composedRoot.decomposedStringWithCanonicalMapping
    let localFile = directory.appendingPathComponent("keep-local-data.bin")
    let originalData = Data([0x00, 0xFF, 0x42, 0x0A])
    try originalData.write(to: localFile)

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then
        targets=$argument
        expects_targets=0
        continue
      fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|revert) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      if [ ! -f status-count ]; then
        : > status-count
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="missing" revision="-1"/></entry></target></status>'
      else
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry></target></status>'
      fi
      exit 0
    fi
    if [ "$command" = revert ]; then
      cp "$targets" revert-targets
      printf '%s\\n' "$*" >> command-log
      exit 0
    fi
    printf 'unexpected arguments: %s\\n' "$*" >&2
    exit 1
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let snapshot = try await client.repairCanonicalAliases(at: directory.path)

    let rawTargets = try Data(contentsOf: directory.appendingPathComponent("revert-targets"))
    let log = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
    #expect(rawTargets.range(of: Data(nfdRoot.utf8)) != nil)
    #expect(log.contains("revert --depth infinity"))
    #expect(!log.contains("--remove-added"))
    #expect(try Data(contentsOf: localFile) == originalData)
    #expect(snapshot.repairableAliasPaths.isEmpty)
}

@Test func repairCanonicalAliasesRejectsAmbiguousVersionedAliasesBeforeRevert() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-ambiguous-alias-repair-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composedRoot = "04 구현"
    let nfdRoot = composedRoot.decomposedStringWithCanonicalMapping
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --verbose --no-ignore --xml"*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="normal" revision="1"/></entry></target></status>'
        ;;
      *)
        printf '%s\\n' "$*" >> command-log
        ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    do {
        _ = try await client.repairCanonicalAliases(at: directory.path)
        Issue.record("모호한 버전 관리 별칭은 되돌리지 않아야 합니다.")
    } catch let SVNError.pathNormalizationCollision(paths) {
        #expect(paths == [composedRoot])
    } catch {
        Issue.record("예상하지 못한 오류: \(error)")
    }

    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("command-log").path))
}

@Test func repairCanonicalAliasesReportsRemainingAliasesAfterRevert() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-persistent-alias-repair-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composedRoot = "04 구현"
    let nfdRoot = composedRoot.decomposedStringWithCanonicalMapping
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    for argument in "$@"; do
      case "$argument" in
        status|revert) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="missing" revision="-1"/></entry></target></status>'
      exit 0
    fi
    if [ "$command" = revert ]; then
      printf '%s\\n' "$*" >> command-log
      exit 0
    fi
    exit 1
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    do {
        _ = try await client.repairCanonicalAliases(at: directory.path)
        Issue.record("별칭이 남아 있으면 검증 오류를 반환해야 합니다.")
    } catch let SVNError.pathAliasRepairFailed(paths) {
        #expect(paths == [composedRoot])
    } catch {
        Issue.record("예상하지 못한 오류: \(error)")
    }
}
