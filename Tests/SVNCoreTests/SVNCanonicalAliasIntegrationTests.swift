import Darwin
import Foundation
import Testing
@testable import SVNCore

@Test func realSVNExplicitlySchedulesRestoresAndCommitsMissingDeletion() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-real-explicit-delete-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("wc", isDirectory: true)
    let verificationCopy = fixture.appendingPathComponent("verify", isDirectory: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runIntegrationCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runIntegrationCommand(svnPath, ["mkdir", repositoryURL + "trunk", "-m", "initial"])
    _ = try runIntegrationCommand(svnPath, ["checkout", repositoryURL + "trunk", workingCopy.path])
    let fileURL = workingCopy.appendingPathComponent("old.txt")
    try Data("old".utf8).write(to: fileURL)
    _ = try runIntegrationCommand(svnPath, ["add", fileURL.path])
    _ = try runIntegrationCommand(svnPath, ["commit", fileURL.path, "-m", "add old"])

    try fileManager.removeItem(at: fileURL)
    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let first = try await client.scheduleDeletion(at: workingCopy.path, paths: ["old.txt"])
    #expect(first.scheduledPaths == ["old.txt"])
    #expect(try await client.status(at: workingCopy.path).first?.item == .deleted)

    _ = try await client.revert(at: workingCopy.path, relativePath: "old.txt")
    #expect(fileManager.fileExists(atPath: fileURL.path))

    try fileManager.removeItem(at: fileURL)
    _ = try await client.scheduleDeletion(at: workingCopy.path, paths: ["old.txt"])
    _ = try await client.commit(at: workingCopy.path, paths: ["old.txt"], message: "delete old")

    _ = try runIntegrationCommand(svnPath, ["checkout", repositoryURL + "trunk", verificationCopy.path])
    #expect(!fileManager.fileExists(atPath: verificationCopy.appendingPathComponent("old.txt").path))
}

@Test func realSVNGlobalIgnorePropertyIsSharedAfterCommit() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-real-global-ignore-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("wc", isDirectory: true)
    let otherCopy = fixture.appendingPathComponent("other", isDirectory: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runIntegrationCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runIntegrationCommand(svnPath, ["mkdir", repositoryURL + "trunk", "-m", "initial"])
    _ = try runIntegrationCommand(svnPath, ["checkout", repositoryURL + "trunk", workingCopy.path])
    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    try await client.addIgnoreRule(
        at: workingCopy.path,
        directory: ".",
        pattern: "*.tmp",
        propertyKind: .global
    )
    _ = try await client.commit(at: workingCopy.path, paths: ["."], message: "share ignore")

    _ = try runIntegrationCommand(svnPath, ["checkout", repositoryURL + "trunk", otherCopy.path])
    try Data("cache".utf8).write(to: otherCopy.appendingPathComponent("cache.tmp"))
    let status = try runIntegrationCommand(svnPath, ["status", "--no-ignore", otherCopy.path])
    #expect(status.contains("I"))
    #expect(status.contains("cache.tmp"))
}

@Test(arguments: [
    "00 사업관리/000 보고관리",
    "00 사업관리/000 보고관리".decomposedStringWithCanonicalMapping,
    "00 사업관리/" + "000 보고관리".decomposedStringWithCanonicalMapping,
])
func realSVNPreservesRepositoryPathSpellingForDecomposedRegisteredSubdirectory(
    repositoryDirectory: String
) async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svn",
        "/usr/local/bin/svn",
        "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svnadmin",
        "/usr/local/bin/svnadmin",
        "/usr/bin/svnadmin",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-real-decomposed-project-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("wc", isDirectory: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runIntegrationCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    let repositoryFile = "005 주간보고/주간보고서.hwp"
    let setupScript = fixture.appendingPathComponent("create-composed-lock-target.zsh")
    try Data("""
    #!/bin/zsh
    set -euo pipefail
    "\(svnPath)" mkdir "\(repositoryURL)\(repositoryDirectory)/005 주간보고" --parents -m initial >/dev/null
    "\(svnPath)" checkout "\(repositoryURL)" "\(workingCopy.path)" >/dev/null
    printf report > "\(workingCopy.path)/\(repositoryDirectory)/\(repositoryFile)"
    "\(svnPath)" add "\(workingCopy.path)/\(repositoryDirectory)/\(repositoryFile)" >/dev/null
    "\(svnPath)" commit "\(workingCopy.path)/\(repositoryDirectory)/\(repositoryFile)" -m 'add report' >/dev/null
    """.utf8).write(to: setupScript)
    _ = try runIntegrationCommand("/bin/zsh", [setupScript.path])

    let registeredPath = (workingCopy.path + "/" + repositoryDirectory)
        .decomposedStringWithCanonicalMapping
    let commandLog = fixture.appendingPathComponent("svn-lock-command-log")
    let wrapper = fixture.appendingPathComponent("logging-svn")
    let wrapperScript = """
    #!/bin/sh
    printf 'PWD:%s\\n' "$(/bin/pwd -P)" >> "\(commandLog.path)"
    for argument in "$@"; do
      printf 'ARG:%s\\n' "$argument" >> "\(commandLog.path)"
    done
    exec "\(svnPath)" "$@"
    """
    try Data(wrapperScript.utf8).write(to: wrapper)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
    let client = SVNClient(
        executablePath: wrapper.path,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )

    let resolvedURL = try await client.workingCopyRepositoryURL(at: registeredPath)
    let existingLock = try await client.lockInfo(
        at: registeredPath,
        relativePath: repositoryFile
    )
    _ = try await client.lock(
        at: registeredPath,
        relativePath: repositoryFile,
        comment: "lock test"
    )
    _ = try await client.unlock(at: registeredPath, relativePath: repositoryFile)

    let localFileURL = URL(fileURLWithPath: registeredPath, isDirectory: true)
        .appendingPathComponent(repositoryFile)
    try Data("changed report".utf8).write(to: localFileURL)
    let fileDiff = try await client.diff(at: registeredPath, relativePath: repositoryFile)
    let fileLogs = try await client.fileLog(at: registeredPath, relativePath: repositoryFile)
    _ = try await client.revert(at: registeredPath, relativePath: repositoryFile)
    try await client.addIgnoreRule(
        at: registeredPath,
        directory: "005 주간보고",
        pattern: "*.tmp"
    )
    try await client.removeIgnoreRule(
        at: registeredPath,
        directory: "005 주간보고",
        pattern: "*.tmp"
    )
    let logData = try Data(contentsOf: commandLog)
    let expectedWorkingDirectorySuffix = Data("/\(workingCopy.lastPathComponent)\n".utf8)
    let expectedTarget = Data("ARG:\(repositoryDirectory)/\(repositoryFile)\n".utf8)
    let expectedTargetCount = logData.split(separator: 0x0A).count {
        Data($0) == Data(expectedTarget.dropLast())
    }

    let decodedRepositoryURL = resolvedURL.removingPercentEncoding ?? resolvedURL
    let resolvedRepositoryDirectory = decodedRepositoryURL.suffix(repositoryDirectory.count)
    #expect(Data(resolvedRepositoryDirectory.utf8) == Data(repositoryDirectory.utf8))
    #expect(existingLock == nil)
    #expect(fileDiff.contains("changed report"))
    #expect(!fileLogs.isEmpty)
    #expect(try Data(contentsOf: localFileURL) == Data("report".utf8))
    #expect(logData.range(of: expectedWorkingDirectorySuffix) != nil)
    #expect(expectedTargetCount == 6)
}

@Test func realSVNCleansMissingAdditionAndRecursivelyCommitsRawNFDDirectory() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svn",
        "/usr/local/bin/svn",
        "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svnadmin",
        "/usr/local/bin/svnadmin",
        "/usr/bin/svnadmin",
    ]))
    let svnlookPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svnlook",
        "/usr/local/bin/svnlook",
        "/usr/bin/svnlook",
    ]))
    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-real-missing-addition-cleanup-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let workingCopy = fixture.appendingPathComponent("wc", isDirectory: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runIntegrationCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runIntegrationCommand(svnPath, ["mkdir", repositoryURL + "plans", "-m", "initial"])
    _ = try runIntegrationCommand(svnPath, ["checkout", repositoryURL, workingCopy.path])

    let staleRoot = workingCopy.appendingPathComponent("stale-added", isDirectory: true)
    try fileManager.createDirectory(at: staleRoot, withIntermediateDirectories: false)
    try Data("stale".utf8).write(to: staleRoot.appendingPathComponent("old.txt"))
    _ = try runIntegrationCommand(svnPath, ["add", staleRoot.path])
    try fileManager.removeItem(at: staleRoot)

    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let cleaned = try await client.workingCopySnapshot(at: workingCopy.path)
    #expect(cleaned.statuses.isEmpty)
    #expect(try runIntegrationCommand(svnPath, ["status", workingCopy.path]).isEmpty)

    let rawDirectory = "0720 기획서".decomposedStringWithCanonicalMapping
    let rawFile = "기획 문서.pdf".decomposedStringWithCanonicalMapping
    let relativeDirectory = "plans/\(rawDirectory)"
    let relativeFile = "\(relativeDirectory)/\(rawFile)"
    let physicalDirectory = workingCopy.path + "/" + relativeDirectory
    let physicalFile = workingCopy.path + "/" + relativeFile
    let expectedBytes = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])
    try createRawDirectory(atPath: physicalDirectory)
    try writeRawFile(expectedBytes, atPath: physicalFile)

    let beforeCommit = try await client.workingCopySnapshot(at: workingCopy.path)
    let selected = try #require(beforeCommit.statuses.first(where: { $0.item == .unversioned }))
    #expect(Data(selected.path.utf8) == Data(relativeDirectory.utf8))
    _ = try await client.commit(
        at: workingCopy.path,
        paths: [selected.path],
        message: "recursive raw path"
    )

    let repositoryTree = try runIntegrationCommand(svnlookPath, ["tree", "--full-paths", repository.path])
    let committedBytes = try runIntegrationCommandData(
        svnlookPath,
        ["cat", repository.path, relativeFile]
    )
    #expect(Data(repositoryTree.utf8).range(of: Data("\(relativeDirectory)/\n".utf8)) != nil)
    #expect(Data(repositoryTree.utf8).range(of: Data("\(relativeFile)\n".utf8)) != nil)
    #expect(committedBytes == expectedBytes)
}

@Test func realSVNCanonicalAliasRepairPreservesBytesAndNonAliasStatuses() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svn",
        "/usr/local/bin/svn",
        "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(firstExecutable(at: [
        "/opt/homebrew/bin/svnadmin",
        "/usr/local/bin/svnadmin",
        "/usr/bin/svnadmin",
    ]))
    let hdiutilPath = "/usr/bin/hdiutil"
    #expect(fileManager.isExecutableFile(atPath: hdiutilPath))

    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-real-alias-repair-\(UUID().uuidString)", isDirectory: true)
    let image = fixture.appendingPathComponent("case-sensitive.dmg")
    let mount = fixture.appendingPathComponent("case-sensitive", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let caseSensitiveWorkingCopy = mount.appendingPathComponent("wc", isDirectory: true)
    let normalWorkingCopy = fixture.appendingPathComponent("normal-wc", isDirectory: true)
    var mounted = false

    try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
    defer {
        if mounted {
            _ = try? runIntegrationCommand(hdiutilPath, ["detach", mount.path])
        }
        try? fileManager.removeItem(at: fixture)
    }

    _ = try runIntegrationCommand(hdiutilPath, [
        "create", "-size", "32m", "-fs", "Case-sensitive APFS",
        "-volname", "SVNCanonicalAliasFixture", "-ov", image.path,
    ])
    _ = try runIntegrationCommand(hdiutilPath, [
        "attach", "-nobrowse", "-mountpoint", mount.path, image.path,
    ])
    mounted = true

    let composedRoot = "04 구현"
    let decomposedRoot = composedRoot.decomposedStringWithCanonicalMapping
    let replacementRoot = "00 사업관리"
    let replacementFile = "주간보고서.hwp"
    let decomposedReplacementFile = replacementFile.decomposedStringWithCanonicalMapping
    let replacementPath = "\(replacementRoot)/\(replacementFile)"
    let modifiedBytes = Data([0xAA, 0x00, 0xFF, 0x42])
    let unversionedBytes = Data([0x99, 0x88, 0x00, 0x77])
    let replacementBytes = Data("replacement-v2".utf8)

    _ = try runIntegrationCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    let repositorySetupScript = fixture.appendingPathComponent("create-composed-repository-path.zsh")
    try Data("""
    #!/bin/zsh
    set -euo pipefail
    "\(svnPath)" mkdir "\(repositoryURL)\(composedRoot)" "\(repositoryURL)\(replacementRoot)" -m initial >/dev/null
    "\(svnPath)" checkout "\(repositoryURL)" "\(caseSensitiveWorkingCopy.path)" >/dev/null
    touch "\(caseSensitiveWorkingCopy.path)/\(composedRoot)/tracked.bin"
    printf 'base-v1' > "\(caseSensitiveWorkingCopy.path)/\(replacementPath)"
    "\(svnPath)" add "\(caseSensitiveWorkingCopy.path)/\(composedRoot)/tracked.bin" "\(caseSensitiveWorkingCopy.path)/\(replacementPath)" >/dev/null
    "\(svnPath)" commit "\(caseSensitiveWorkingCopy.path)/\(composedRoot)/tracked.bin" "\(caseSensitiveWorkingCopy.path)/\(replacementPath)" -m tracked >/dev/null
    rm "\(caseSensitiveWorkingCopy.path)/\(replacementPath)"
    printf 'replacement-v2' > "\(caseSensitiveWorkingCopy.path)/\(replacementRoot)/\(decomposedReplacementFile)"
    mkdir -p "\(caseSensitiveWorkingCopy.path)/\(decomposedRoot)"
    touch "\(caseSensitiveWorkingCopy.path)/\(decomposedRoot)/scheduled.bin"
    "\(svnPath)" add "\(caseSensitiveWorkingCopy.path)/\(decomposedRoot)" >/dev/null
    """.utf8).write(to: repositorySetupScript)
    _ = try runIntegrationCommand("/bin/zsh", [repositorySetupScript.path])

    try fileManager.createDirectory(at: normalWorkingCopy, withIntermediateDirectories: true)
    try fileManager.copyItem(
        at: caseSensitiveWorkingCopy.appendingPathComponent(".svn", isDirectory: true),
        to: normalWorkingCopy.appendingPathComponent(".svn", isDirectory: true)
    )
    let physicalRootPath = normalWorkingCopy.path + "/" + composedRoot
    try createRawDirectory(atPath: physicalRootPath)
    let normalTrackedPath = physicalRootPath + "/tracked.bin"
    let normalUnversionedPath = physicalRootPath + "/unversioned.bin"
    let physicalReplacementRootPath = normalWorkingCopy.path + "/" + replacementRoot
    try createRawDirectory(atPath: physicalReplacementRootPath)
    let normalReplacementPath = physicalReplacementRootPath + "/" + decomposedReplacementFile
    try writeRawFile(modifiedBytes, atPath: normalTrackedPath)
    try writeRawFile(unversionedBytes, atPath: normalUnversionedPath)
    try writeRawFile(replacementBytes, atPath: normalReplacementPath)

    _ = try runIntegrationCommand(hdiutilPath, ["detach", mount.path])
    mounted = false

    let commandLog = fixture.appendingPathComponent("svn-command-log")
    let wrapper = fixture.appendingPathComponent("logging-svn")
    let wrapperScript = """
    #!/bin/sh
    expect_targets=0
    for argument in "$@"; do
      printf 'ARG:%s\\n' "$argument" >> "\(commandLog.path)"
      if [ "$expect_targets" = 1 ]; then
        while IFS= read -r target || [ -n "$target" ]; do
          printf 'TARGET:%s\\n' "$target" >> "\(commandLog.path)"
        done < "$argument"
        expect_targets=0
      elif [ "$argument" = --targets ]; then
        expect_targets=1
      fi
    done
    exec "\(svnPath)" "$@"
    """
    try Data(wrapperScript.utf8).write(to: wrapper)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)

    let client = SVNClient(
        executablePath: wrapper.path,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let before = try await client.workingCopySnapshot(at: normalWorkingCopy.path)
    let preservedPaths = Set([
        "\(composedRoot)/tracked.bin",
        "\(composedRoot)/unversioned.bin",
        replacementPath,
    ])
    let beforeStatuses = before.statuses.filter { preservedPaths.contains($0.path) }

    #expect(before.repairableAliasPaths.map { Data($0.utf8) } == [Data(decomposedRoot.utf8)])
    #expect(beforeStatuses == [
        SVNStatusEntry(path: replacementPath, item: .modified, revision: "2", nodeKind: .file),
        SVNStatusEntry(path: "\(composedRoot)/tracked.bin", item: .modified, revision: "2", nodeKind: .file),
        SVNStatusEntry(path: "\(composedRoot)/unversioned.bin", item: .unversioned, nodeKind: .file),
    ])

    let after = try await client.repairCanonicalAliases(at: normalWorkingCopy.path)
    let afterStatuses = after.statuses.filter { preservedPaths.contains($0.path) }
    let logData = try Data(contentsOf: commandLog)
    let log = try #require(String(data: logData, encoding: .utf8))

    #expect(try Data(contentsOf: URL(fileURLWithPath: normalTrackedPath)) == modifiedBytes)
    #expect(try Data(contentsOf: URL(fileURLWithPath: normalUnversionedPath)) == unversionedBytes)
    #expect(afterStatuses == beforeStatuses)
    #expect(after.collisions.isEmpty)
    #expect(log.contains("ARG:revert\nARG:--depth\nARG:empty\n"))
    #expect(!log.contains("ARG:--remove-added\n"))
    let exactTargetBlock = Data(
        ("TARGET:\(decomposedRoot)/scheduled.bin\n"
            + "TARGET:\(decomposedRoot)/tracked.bin\n"
            + "TARGET:\(decomposedRoot)\n").utf8
    )
    #expect(logData.range(of: exactTargetBlock) != nil)

    _ = try await client.commit(
        at: normalWorkingCopy.path,
        paths: [replacementPath],
        message: "canonical file replacement"
    )
    let encodedReplacementURL = try #require(
        URL(string: repositoryURL + replacementPath)?.absoluteString
    )
    let repositoryContents = try runIntegrationCommand(svnPath, ["cat", encodedReplacementURL])
    let committedSnapshot = try await client.workingCopySnapshot(at: normalWorkingCopy.path)

    #expect(repositoryContents == "replacement-v2")
    #expect(try Data(contentsOf: URL(fileURLWithPath: normalReplacementPath)) == replacementBytes)
    #expect(!committedSnapshot.statuses.contains { $0.path == replacementPath })
}

private func firstExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

private func createRawDirectory(atPath path: String) throws {
    let result = path.withCString { Darwin.mkdir($0, 0o755) }
    guard result == 0 else {
        throw IntegrationPOSIXError(operation: "mkdir", path: path, code: errno)
    }
}

private func writeRawFile(_ data: Data, atPath path: String) throws {
    let descriptor = path.withCString {
        Darwin.open($0, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
        throw IntegrationPOSIXError(operation: "open", path: path, code: errno)
    }
    defer { Darwin.close(descriptor) }

    try data.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let written = Darwin.write(
                descriptor,
                baseAddress.advanced(by: offset),
                bytes.count - offset
            )
            guard written > 0 else {
                throw IntegrationPOSIXError(operation: "write", path: path, code: errno)
            }
            offset += written
        }
    }
}

@discardableResult
private func runIntegrationCommand(
    _ executablePath: String,
    _ arguments: [String]
) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw IntegrationCommandError(
            command: ([executablePath] + arguments).joined(separator: " "),
            output: text
        )
    }
    return text
}

private func runIntegrationCommandData(
    _ executablePath: String,
    _ arguments: [String]
) throws -> Data {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw IntegrationCommandError(
            command: ([executablePath] + arguments).joined(separator: " "),
            output: String(decoding: errorData, as: UTF8.self)
        )
    }
    return data
}

private struct IntegrationCommandError: LocalizedError {
    let command: String
    let output: String

    var errorDescription: String? {
        "Integration command failed: \(command)\n\(output)"
    }
}

private struct IntegrationPOSIXError: LocalizedError {
    let operation: String
    let path: String
    let code: Int32

    var errorDescription: String? {
        "\(operation) failed for \(path) with errno \(code)"
    }
}
