import Darwin
import Foundation
import Testing
@testable import SVNCore

@Test func rollbackRootsPreservePreexistingScheduledAdditionParent() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="1"/></entry>
      <entry path="기존 추가 부모"><wc-status item="added" revision="-1"/></entry>
      <entry path="기존 추가 부모/이번 자식"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))
    let roots = SVNClient.additionRollbackRoots(
        ["기존 추가 부모/이번 자식"],
        versionedPathsByCanonicalKey: snapshot.versionedPathsByCanonicalKey,
        preexistingScheduledAdditionPaths: snapshot.scheduledAdditionPaths
    )

    #expect(snapshot.scheduledAdditionPaths == ["기존 추가 부모"])
    #expect(roots == ["기존 추가 부모/이번 자식"])
}

@Test func targetFilesEscapePegSyntaxAndRejectLineBreaks() throws {
    #expect(SVNClient.svnPathEscapingPegSyntax("보고서@최종.hwp") == "보고서@최종.hwp@")
    #expect(SVNClient.svnPathEscapingPegSyntax("보고서.hwp") == "보고서.hwp")
    #expect(try SVNClient.svnTargetsFileContents(["보고서@최종.hwp"]) == Data("보고서@최종.hwp@\n".utf8))
    #expect(throws: SVNError.self) {
        _ = try SVNClient.svnTargetsFileContents(["보고서\n최종.hwp"])
    }
}

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
    #expect(result.contains("checkout -- https://example.test/svn/project ."))
}

@Test func streamsCheckoutOutputBeforeCommandCompletes() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-checkout-progress-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    : > checkout-started
    printf 'A    Sources/App.swift\n'
    while [ ! -f continue-checkout ]; do
      sleep 0.02
    done
    printf 'Checked out revision 42.\n'
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let recorder = CheckoutOutputRecorder()
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let destination = directory.appendingPathComponent("checkout", isDirectory: true)
    let checkout = Task {
        try await client.checkout(
            repositoryURL: "https://example.test/svn/project",
            destinationPath: destination.path,
            progress: { output in
                recorder.append(output)
            }
        )
    }

    let processStarted = await waitUntil(timeout: .seconds(30)) {
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("checkout-started").path)
    }
    #expect(processStarted)
    let receivedFirstPath = if processStarted {
        await waitUntil { recorder.output.contains("A    Sources/App.swift") }
    } else {
        false
    }
    #expect(receivedFirstPath)
    try Data().write(to: destination.appendingPathComponent("continue-checkout"))

    let result = try await checkout.value
    #expect(result.contains("Checked out revision 42."))
    #expect(recorder.output.contains("Checked out revision 42."))
}

@Test func actorCanServeAnotherCommandWhileCheckoutIsRunning() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-nonblocking-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"checkout --"*)
        : > checkout-started
        while [ ! -f continue-checkout ]; do sleep 0.02; done
        ;;
      *"info --show-item wc-root"*)
        : > info-finished
        printf '%s\\n' "$PWD"
        ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let destination = directory.appendingPathComponent("checkout", isDirectory: true)
    let checkout = Task {
        try await client.checkout(
            repositoryURL: "https://example.test/svn/project",
            destinationPath: destination.path
        )
    }
    #expect(await waitUntil(timeout: .seconds(15)) {
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("checkout-started").path)
    })

    let validation = Task { try await client.validateWorkingCopy(at: destination.path) }
    let infoFinished = await waitUntil(timeout: .seconds(5)) {
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("info-finished").path)
    }
    try Data().write(to: destination.appendingPathComponent("continue-checkout"))
    _ = try await checkout.value
    try await validation.value

    #expect(infoFinished)
}

@Test func cancellingCommandTerminatesProcess() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-cancellation-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    : > command-started
    while :; do sleep 0.05; done
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let task = Task {
        try await client.validateWorkingCopy(at: directory.path)
    }
    #expect(await waitUntil(timeout: .seconds(15)) {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("command-started").path)
    })
    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}

@Test func passwordPipeClosureReturnsCommandFailureInsteadOfCrashing() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-password-epipe-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    try Data("#!/bin/sh\nexit 1\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )

    await #expect(throws: SVNError.self) {
        _ = try await client.checkout(
            repositoryURL: "https://example.test/svn/project",
            destinationPath: directory.appendingPathComponent("checkout").path,
            credentials: SVNCredentials(username: "user", password: String(repeating: "x", count: 1_000_000))
        )
    }
}

@Test func ignorePatternStartingWithDashIsReadFromFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-property-option-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    value_file=
    previous=
    for argument in "$@"; do
      [ "$previous" = "--file" ] && value_file=$argument
      case "$argument" in propget|propset) command=$argument ;; esac
      previous=$argument
    done
    if [ "$command" = propget ]; then
      printf '%s\\n' 'svn: warning: W200017: Property not found' >&2
      exit 1
    fi
    if [ "$command" = propset ]; then
      printf '%s\\n' "$*" > propset-arguments
      cp "$value_file" propset-value
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

    try await client.addIgnoreRule(at: directory.path, directory: ".", pattern: "--dangerous")

    let arguments = try String(
        contentsOf: directory.appendingPathComponent("propset-arguments"),
        encoding: .utf8
    )
    let value = try String(
        contentsOf: directory.appendingPathComponent("propset-value"),
        encoding: .utf8
    )
    #expect(arguments.contains("propset svn:ignore --file"))
    #expect(!arguments.contains("--dangerous"))
    #expect(value == "--dangerous\n")
}

private func waitUntil(
    timeout: Duration = .seconds(5),
    condition: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

private final class CheckoutOutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOutput = ""

    var output: String {
        lock.withLock { storedOutput }
    }

    func append(_ output: String) {
        lock.withLock { storedOutput += output }
    }
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

@Test func revisionDiffPreservesNFCRepositoryPathBytes() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-revision-nfc-path-test-\(UUID().uuidString)", isDirectory: true)
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
    let nfcFileName = "주간보고서.hwp"
    let result = try await client.revisionDiff(
        at: directory.path,
        revision: "13306",
        repositoryPath: "/한글/project/주간보고/\(nfcFileName)",
        workingCopyRepositoryPath: "/%ED%95%9C%EA%B8%80/project",
        pegRevision: "13306"
    )

    let resultData = Data(result.utf8)
    #expect(resultData.range(of: Data("^/%ED%95%9C%EA%B8%80/project/주간보고/\(nfcFileName)@13306".utf8)) != nil)
    #expect(resultData.range(of: Data("주간보고서.hwp".decomposedStringWithCanonicalMapping.utf8)) == nil)
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

@Test func workingCopySnapshotTreatsDifferentCanonicalAliasBytesAsModified() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-replacement-modified-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composed = "주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    try writeCredentialTestRawFile(
        Data([0xFF, 0x00, 0x41]),
        atPath: directory.path + "/" + decomposed
    )
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    printf '%s\n' "$*" >> command-log
    case "$*" in
      *"status --verbose --no-ignore --xml"*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="\(composed)"><wc-status item="missing" revision="7"/></entry><entry path="\(decomposed)"><wc-status item="unversioned"/></entry></target></status>'
        ;;
      *"cat --revision BASE -- "*) printf '\001\002\003' ;;
      *) exit 1 ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let snapshot = try await client.workingCopySnapshot(at: directory.path)
    let commandLog = try String(
        contentsOf: directory.appendingPathComponent("command-log"),
        encoding: .utf8
    )
    let commandLogData = try Data(contentsOf: directory.appendingPathComponent("command-log"))

    #expect(snapshot.canonicalFileReplacements.count == 1)
    #expect(commandLog.contains("cat --revision BASE"))
    #expect(commandLogData.range(of: Data(composed.utf8)) != nil)
    #expect(commandLogData.range(of: Data(decomposed.utf8)) == nil)
    #expect(snapshot.statuses == [
        SVNStatusEntry(path: composed, item: .modified, revision: "7", nodeKind: .file),
    ])

    let browserEntries = try await client.workingCopyEntries(at: directory.path)
    let browserEntry = try #require(browserEntries.first {
        Data($0.path.utf8) == Data(decomposed.utf8)
    })
    #expect(browserEntry.status == "modified")
    #expect(browserEntry.revision == "7")
    #expect(Data(browserEntry.repositoryRelativePath.utf8) == Data(composed.utf8))
    #expect(!browserEntries.contains {
        Data($0.path.utf8) == Data(composed.utf8) && $0.status == "missing"
    })
}

@Test func workingCopySnapshotAnnotatesUnversionedNodeKinds() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-unversioned-node-kind-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let folder = directory.appendingPathComponent("새 폴더", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("문서.pdf"))
    try Data().write(to: directory.appendingPathComponent("새 파일.pdf"))

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --verbose --no-ignore --xml"*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="새 폴더"><wc-status item="unversioned"/></entry><entry path="새 파일.pdf"><wc-status item="unversioned"/></entry></target></status>'
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
    let snapshot = try await client.workingCopySnapshot(at: directory.path)
    let byPath = Dictionary(uniqueKeysWithValues: snapshot.statuses.map { ($0.path, $0) })

    #expect(byPath["새 폴더"]?.nodeKind == .directory)
    #expect(byPath["새 파일.pdf"]?.nodeKind == .file)
}

private func writeCredentialTestRawFile(_ data: Data, atPath path: String) throws {
    let descriptor = path.withCString {
        Darwin.open($0, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer { Darwin.close(descriptor) }
    try data.withUnsafeBytes { bytes in
        guard let address = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, address.advanced(by: offset), bytes.count - offset)
            guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
            offset += count
        }
    }
}

@Test func workingCopySnapshotDropsCanonicalAliasReplacementWithBaseBytes() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-replacement-normal-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composed = "주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    try Data([0xFF, 0x00, 0x41]).write(to: directory.appendingPathComponent(decomposed))
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --verbose --no-ignore --xml"*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="\(composed)"><wc-status item="missing" revision="7"/></entry><entry path="\(decomposed)"><wc-status item="unversioned"/></entry></target></status>'
        ;;
      *"cat --revision BASE -- "*) printf '\\377\\000A' ;;
      *) exit 1 ;;
    esac
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let snapshot = try await client.workingCopySnapshot(at: directory.path)

    #expect(snapshot.statuses.isEmpty)

    let browserEntries = try await client.workingCopyEntries(at: directory.path)
    let browserEntry = try #require(browserEntries.first {
        Data($0.path.utf8) == Data(decomposed.utf8)
    })
    #expect(browserEntry.status == "normal")
    #expect(browserEntry.revision == "7")
    #expect(Data(browserEntry.repositoryRelativePath.utf8) == Data(composed.utf8))
    #expect(!browserEntries.contains {
        Data($0.path.utf8) == Data(composed.utf8) && $0.status == "missing"
    })
}

@Test func workingCopySnapshotAutomaticallyCleansMissingScheduledAddition() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-missing-addition-cleanup-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let missingRoot = "새 폴더".decomposedStringWithCanonicalMapping
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then targets=$argument; expects_targets=0; continue; fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|revert) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      if [ -f cleaned ]; then
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry></target></status>'
      else
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(missingRoot)"><wc-status item="missing" revision="-1"/></entry><entry path="\(missingRoot)/문서.pdf"><wc-status item="missing" revision="-1"/></entry></target></status>'
      fi
      exit 0
    fi
    if [ "$command" = revert ]; then
      cp "$targets" cleanup-targets
      printf '%s\n' "$*" > cleanup-command
      : > cleaned
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
    let snapshot = try await client.workingCopySnapshot(at: directory.path)

    #expect(snapshot.statuses.isEmpty)
    #expect(snapshot.missingScheduledAdditionCleanupTargets.isEmpty)
    #expect(try Data(contentsOf: directory.appendingPathComponent("cleanup-targets")) == Data("\(missingRoot)\n".utf8))
    #expect(try String(contentsOf: directory.appendingPathComponent("cleanup-command"), encoding: .utf8).contains("revert --depth infinity"))
}

@Test func failedMissingAdditionCleanupLeavesOneVisibleRoot() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-missing-addition-cleanup-failure-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case " $* " in
      *" status "*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="사라진 폴더"><wc-status item="missing" revision="-1"/></entry><entry path="사라진 폴더/문서.pdf"><wc-status item="missing" revision="-1"/></entry></target></status>'
        exit 0 ;;
      *" revert "*) : > cleanup-attempted; printf 'revert failed\n' >&2; exit 1 ;;
    esac
    exit 1
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let snapshot = try await client.workingCopySnapshot(at: directory.path)

    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cleanup-attempted").path))
    #expect(snapshot.statuses == [
        SVNStatusEntry(path: "사라진 폴더", item: .missing, revision: "-1"),
    ])
}

@Test func existingPathsAndSymlinksAreNeverAutomaticallyCleaned() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-existing-addition-cleanup-guard-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try FileManager.default.createDirectory(at: directory.appendingPathComponent("존재하는 폴더"), withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent("끊긴 링크"),
        withDestinationURL: directory.appendingPathComponent("없는 대상")
    )
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case " $* " in
      *" status "*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="존재하는 폴더"><wc-status item="missing" revision="-1"/></entry><entry path="끊긴 링크"><wc-status item="missing" revision="-1"/></entry></target></status>'
        exit 0 ;;
      *" revert "*) : > unsafe-cleanup-attempted; exit 0 ;;
    esac
    exit 1
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let snapshot = try await client.workingCopySnapshot(at: directory.path)

    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("unsafe-cleanup-attempted").path))
    #expect(snapshot.statuses.count == 2)
}

@Test func partialMissingAdditionCleanupReturnsFreshRemainingState() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-partial-missing-addition-cleanup-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then targets=$argument; expects_targets=0; continue; fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|revert) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry>'
      [ -f first-cleaned ] || printf '%s' '<entry path="a-stale"><wc-status item="missing" revision="-1"/></entry>'
      printf '%s' '<entry path="b-stale"><wc-status item="missing" revision="-1"/></entry></target></status>'
      exit 0
    fi
    if [ "$command" = revert ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        if [ "$target" = a-stale ]; then : > first-cleaned; fi
        if [ "$target" = b-stale ]; then : > second-attempted; printf 'second failed\n' >&2; exit 1; fi
      done < "$targets"
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
    let snapshot = try await client.workingCopySnapshot(at: directory.path)

    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("first-cleaned").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second-attempted").path))
    #expect(snapshot.statuses == [
        SVNStatusEntry(path: "b-stale", item: .missing, revision: "-1"),
    ])
}

@Test func workingCopySnapshotDoesNotTreatCanonicalAliasDirectoryAsFileReplacement() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-replacement-directory-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composed = "주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent(decomposed),
        withIntermediateDirectories: false
    )
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --verbose --no-ignore --xml"*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="\(composed)"><wc-status item="missing" revision="7"/></entry><entry path="\(decomposed)"><wc-status item="unversioned"/></entry></target></status>'
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
    let snapshot = try await client.workingCopySnapshot(at: directory.path)

    #expect(snapshot.statuses == [
        SVNStatusEntry(path: composed, item: .missing, revision: "7", nodeKind: .directory),
    ])
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
      printf '<?xml version="1.0"?><status><target path="."><entry path="Old"><wc-status item="deleted" revision="1"/></entry><entry path="Old/file.txt"><wc-status item="deleted" revision="1"/></entry><entry path="Old/nested/file.txt"><wc-status item="deleted" revision="1"/></entry><entry path="New"><wc-status item="unversioned"/></entry><entry path="Application/file.swift"><wc-status item="modified" revision="1"/></entry><entry path="App/file.swift"><wc-status item="modified" revision="1"/></entry></target></status>'
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
    #expect(lines.filter { $0 == "delete" }.isEmpty)
    #expect(lines.filter { $0 == "commit" }.count == 1)
    #expect(lines.contains("add:New"))
    #expect(lines.contains("commit:App/file.swift"))
    #expect(lines.contains("commit:Application/file.swift"))
    #expect(lines.contains("commit:New"))
    #expect(lines.contains("commit:Old"))
}

@Test func schedulesMissingDeletionBeforeCommitAndValidatesDeletedState() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-schedule-delete-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    targets=
    expects_targets=0
    for argument in "$@"; do
      if [ "$expects_targets" = 1 ]; then targets=$argument; expects_targets=0; continue; fi
      case "$argument" in
        --targets) expects_targets=1 ;;
        status|delete) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      if [ -f deletion-scheduled ]; then item=deleted; else item=missing; fi
      printf '<?xml version="1.0"?><status><target path="."><entry path="Old"><wc-status item="%s" revision="1" kind="dir"/></entry><entry path="Old/file.txt"><wc-status item="%s" revision="1" kind="file"/></entry></target></status>' "$item" "$item"
      exit 0
    fi
    printf '%s\\n' "$command" >> command-log
    while IFS= read -r target || [ -n "$target" ]; do
      printf '%s:%s\\n' "$command" "$target" >> command-log
    done < "$targets"
    touch deletion-scheduled
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    let result = try await client.scheduleDeletion(
        at: directory.path,
        paths: ["Old", "Old/file.txt"]
    )

    #expect(result.scheduledPaths == ["Old"])
    #expect(result.failedPaths.isEmpty)
    let log = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
    #expect(log.contains("delete:Old"))
    #expect(!log.contains("delete:Old/file.txt"))
}

@Test func commitRejectsMissingPathWithoutDeleteOrCommit() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-reject-missing-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    case "$*" in
      *"status --verbose --no-ignore --xml"*)
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="Old.txt"><wc-status item="missing" revision="1"/></entry></target></status>'
        exit 0
        ;;
    esac
    printf '%s\\n' "$*" >> command-log
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    await #expect(throws: SVNError.self) {
        _ = try await client.commit(at: directory.path, paths: ["Old.txt"], message: "삭제")
    }
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("command-log").path))
}

@Test func commitMaterializesCanonicalFileReplacementBeforeCommit() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-replacement-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composed = "주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    let replacementBytes = Data([0xFF, 0x00, 0x41, 0x42])
    try replacementBytes.write(to: directory.appendingPathComponent(decomposed))
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
        status|cat|revert|commit) command=$argument ;;
      esac
    done
    printf '%s\n' "$command" >> command-log
    if [ "$command" = status ]; then
      if [ -f committed ]; then
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="8"/></entry><entry path="\(composed)"><wc-status item="normal" revision="8"/></entry></target></status>'
      elif [ -f rebound ]; then
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="\(composed)"><wc-status item="modified" revision="7"/></entry></target></status>'
      else
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="\(composed)"><wc-status item="missing" revision="7"/></entry><entry path="\(decomposed)"><wc-status item="unversioned"/></entry></target></status>'
      fi
      exit 0
    fi
    if [ "$command" = cat ]; then
      printf 'base'
      exit 0
    fi
    if [ -n "$targets" ]; then
      while IFS= read -r target || [ -n "$target" ]; do
        printf '%s:%s\n' "$command" "$target" >> target-log
      done < "$targets"
    fi
    if [ "$command" = revert ]; then
      backup_found=0
      for backup in "$TMPDIR"/svn-mac-file-replacement-backup-*/replacement; do
        if [ -f "$backup" ]; then
          backup_found=1
          break
        fi
      done
      [ "$backup_found" = 1 ] || exit 2
      printf 'base' > '\(composed)'
      : > rebound
      exit 0
    fi
    if [ "$command" = commit ]; then
      : > committed
      printf 'committed\n'
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
    _ = try await client.commit(
        at: directory.path,
        paths: [composed],
        message: "HWP 대치"
    )

    let commands = try String(
        contentsOf: directory.appendingPathComponent("command-log"),
        encoding: .utf8
    ).split(whereSeparator: \.isNewline).map(String.init)
    let targets = try String(
        contentsOf: directory.appendingPathComponent("target-log"),
        encoding: .utf8
    )
    #expect(commands == ["status", "cat", "revert", "status", "commit", "status"])
    #expect(targets.contains("revert:\(composed)"))
    #expect(targets.contains("commit:\(composed)"))
    #expect(try Data(contentsOf: directory.appendingPathComponent(composed)) == replacementBytes)
}

@Test func failedReplacementRevertRestoresAliasBytesAndRemovesBackup() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-replacement-rollback-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let composed = "주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    let replacementBytes = Data([0xDE, 0xAD, 0x00, 0xBE, 0xEF])
    try replacementBytes.write(to: directory.appendingPathComponent(decomposed))
    try replacementBytes.write(to: directory.appendingPathComponent("expected-backup"))
    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    for argument in "$@"; do
      case "$argument" in
        status|cat|revert|commit) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="7"/></entry><entry path="\(composed)"><wc-status item="missing" revision="7"/></entry><entry path="\(decomposed)"><wc-status item="unversioned"/></entry></target></status>'
      exit 0
    fi
    if [ "$command" = cat ]; then
      printf 'base'
      exit 0
    fi
    if [ "$command" = revert ]; then
      for backup in "$TMPDIR"/svn-mac-file-replacement-backup-*/replacement; do
        if [ -f "$backup" ] && cmp -s "$backup" expected-backup; then
          printf '%s' "$backup" > observed-backup
          break
        fi
      done
      printf 'revert failed\n' >&2
      exit 1
    fi
    exit 1
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    await #expect(throws: SVNError.self) {
        _ = try await client.commit(at: directory.path, paths: [composed], message: "실패")
    }

    let backupPath = try String(
        contentsOf: directory.appendingPathComponent("observed-backup"),
        encoding: .utf8
    )
    #expect(try Data(contentsOf: directory.appendingPathComponent(decomposed)) == replacementBytes)
    #expect(!FileManager.default.fileExists(atPath: backupPath))
}

@Test func commitMapsDecomposedSelectionToExistingPrecomposedAncestor() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-normalized-commit-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let precomposedDirectory = "구현"
    let decomposedDirectory = precomposedDirectory.decomposedStringWithCanonicalMapping
    let decomposedNewDirectory = "0720 기획서".decomposedStringWithCanonicalMapping
    let selectedPath = "\(decomposedDirectory)/\(decomposedNewDirectory)"
    let expectedPath = "\(precomposedDirectory)/\(decomposedNewDirectory)"
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
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(precomposedDirectory)"><wc-status item="normal" revision="1"/></entry><entry path="\(selectedPath)"><wc-status item="unversioned"/></entry></target></status>'
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
        paths: [selectedPath],
        message: "정규화 경로"
    )

    let log = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
    #expect(log.contains("add:\(expectedPath)"))
    #expect(log.contains("commit:\(expectedPath)"))
    let rawLines = log.split(whereSeparator: \.isNewline).map { Data($0.utf8) }
    #expect(rawLines.contains(Data("add:\(expectedPath)".utf8)))
    #expect(!rawLines.contains(Data("add:\(expectedPath.precomposedStringWithCanonicalMapping)".utf8)))
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
    #expect(commands == ["status", "revert", "status", "add", "commit", "status"])

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

@Test func commitClassifiesOutOfDateDirectoryWithoutDiscardingSVNDetails() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-commit-out-of-date-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("fake-svn")
    let script = """
    #!/bin/sh
    command=
    for argument in "$@"; do
      case "$argument" in
        status|commit) command=$argument ;;
      esac
    done
    if [ "$command" = status ]; then
      printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="13295"/></entry><entry path="generated"><wc-status item="deleted" revision="13295"/></entry></target></status>'
      exit 0
    fi
    if [ "$command" = commit ]; then
      printf '%s\n' 'svn: E155011: Directory generated is out of date' >&2
      printf '%s\n' 'svn: E170004: Directory generated is out of date' >&2
      exit 1
    fi
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    do {
        _ = try await client.commit(
            at: directory.path,
            paths: ["generated"],
            message: "디렉터리 삭제"
        )
        Issue.record("out-of-date 커밋이 전용 오류로 거부되어야 합니다.")
    } catch let SVNError.workingCopyOutOfDate(details) {
        #expect(details.contains("E155011"))
        #expect(details.contains("E170004"))
        #expect(details.contains("generated is out of date"))
    } catch {
        Issue.record("예상하지 못한 오류: \(error)")
    }
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

@Test func commitValidatesAfterRepositorySuccessWithoutRollingBackScheduling() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-post-commit-validation-test-\(UUID().uuidString)", isDirectory: true)
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
        status|add|commit|revert) command=$argument ;;
      esac
    done
    printf '%s\n' "$command" >> command-log
    if [ "$command" = status ]; then
      if [ ! -f committed ]; then
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="새 파일.bin"><wc-status item="unversioned"/></entry></target></status>'
      else
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="2"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="2"/></entry><entry path="\(nfdRoot)"><wc-status item="normal" revision="2"/></entry></target></status>'
      fi
      exit 0
    fi
    if [ "$command" = commit ]; then
      : > committed
      printf 'Committed revision 2.\n'
      exit 0
    fi
    exit 0
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: directory.appendingPathComponent("svn-config").path
    )
    do {
        _ = try await client.commit(at: directory.path, paths: ["새 파일.bin"], message: "검증")
        Issue.record("커밋 뒤 충돌은 완료 경고로 반환되어야 합니다.")
    } catch let SVNError.commitSucceededWithValidationWarning(output, details) {
        #expect(output == "Committed revision 2.\n")
        #expect(details.contains(composedRoot))
    } catch {
        Issue.record("예상하지 못한 오류: \(error)")
    }

    let commands = try String(contentsOf: directory.appendingPathComponent("command-log"), encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    #expect(commands == ["status", "add", "commit", "status"])
    #expect(!commands.contains("revert"))
}

@Test func repairCanonicalAliasesRevertsExactScheduledNFDEntriesWithEmptyDepth() async throws {
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
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="missing" revision="-1"/></entry><entry path="\(nfdRoot)/하위.bin"><wc-status item="added" revision="-1"/></entry></target></status>'
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
    #expect(rawTargets == Data("\(nfdRoot)/하위.bin\n\(nfdRoot)\n".utf8))
    #expect(log.contains("revert --depth empty"))
    #expect(!log.contains("--remove-added"))
    #expect(try Data(contentsOf: localFile) == originalData)
    #expect(snapshot.repairableAliasPaths.isEmpty)
}

@Test func repairCanonicalAliasesRejectsNewAmbiguityFoundByPostcheck() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-new-ambiguity-repair-test-\(UUID().uuidString)", isDirectory: true)
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
      if [ ! -f repaired ]; then
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="missing" revision="-1"/></entry></target></status>'
      else
        printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="1"/></entry><entry path="\(composedRoot)"><wc-status item="normal" revision="1"/></entry><entry path="\(nfdRoot)"><wc-status item="normal" revision="1"/></entry></target></status>'
      fi
      exit 0
    fi
    if [ "$command" = revert ]; then
      : > repaired
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
        Issue.record("정리 뒤 새로 확인된 모호한 경로는 성공으로 처리하면 안 됩니다.")
    } catch let SVNError.pathNormalizationCollision(paths) {
        #expect(paths == [composedRoot])
    } catch {
        Issue.record("예상하지 못한 오류: \(error)")
    }
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
