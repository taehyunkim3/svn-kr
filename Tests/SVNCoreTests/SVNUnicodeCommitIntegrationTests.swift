import Foundation
import Darwin
import Testing
@testable import SVNCore

@Test func realSVNCommitStoresNewNFDFileAsNFC() async throws {
    let fixture = try UnicodeCommitFixture()
    defer { fixture.remove() }
    let nfcName = "한글파일.txt"
    let nfdName = nfcName.decomposedStringWithCanonicalMapping
    try writeUnicodeIntegrationFile(
        Data("new".utf8),
        atPath: fixture.workingCopy.path + "/" + nfdName
    )

    _ = try await fixture.client.commit(
        at: fixture.workingCopy.path,
        paths: [nfdName],
        message: "NFC file"
    )

    let names = try repositoryNames(fixture, recursive: false)
    #expect(names.map { Data($0.utf8) } == [Data(nfcName.utf8)])
}

@Test func realSVNCommitRecursivelyStoresNFDDirectoryAndChildAsNFC() async throws {
    let fixture = try UnicodeCommitFixture()
    defer { fixture.remove() }
    let nfcDirectory = "한글폴더"
    let nfdDirectory = nfcDirectory.decomposedStringWithCanonicalMapping
    let nfcFile = "하위파일.txt"
    let nfdFile = nfcFile.decomposedStringWithCanonicalMapping
    try createUnicodeIntegrationDirectory(
        atPath: fixture.workingCopy.path + "/" + nfdDirectory
    )
    try writeUnicodeIntegrationFile(
        Data("nested".utf8),
        atPath: fixture.workingCopy.path + "/" + nfdDirectory + "/" + nfdFile
    )

    _ = try await fixture.client.commit(
        at: fixture.workingCopy.path,
        paths: [nfdDirectory],
        message: "NFC tree"
    )

    let names = try repositoryNames(fixture, recursive: true)
    #expect(names.map { Data($0.utf8) } == [
        Data("\(nfcDirectory)/".utf8),
        Data("\(nfcDirectory)/\(nfcFile)".utf8),
    ])
}

@Test func realSVNCommitPreservesExistingVersionedNFDPathWhileNormalizingNewPath() async throws {
    let fixture = try UnicodeCommitFixture()
    defer { fixture.remove() }
    let existingNFCName = "기존파일.txt"
    let existingNFDName = existingNFCName.decomposedStringWithCanonicalMapping
    let existingPath = fixture.workingCopy.path + "/" + existingNFDName
    try writeUnicodeIntegrationFile(Data("old".utf8), atPath: existingPath)
    _ = try runUnicodeIntegrationCommand(fixture.svnPath, ["add", existingPath])
    _ = try runUnicodeIntegrationCommand(
        fixture.svnPath,
        ["commit", existingPath, "-m", "existing NFD"]
    )

    try writeUnicodeIntegrationFile(Data("changed".utf8), atPath: existingPath)
    let newNFCName = "신규파일.txt"
    let newNFDName = newNFCName.decomposedStringWithCanonicalMapping
    try writeUnicodeIntegrationFile(
        Data("new".utf8),
        atPath: fixture.workingCopy.path + "/" + newNFDName
    )

    _ = try await fixture.client.commit(
        at: fixture.workingCopy.path,
        paths: [existingNFDName, newNFDName],
        message: "mixed paths"
    )

    let names = try repositoryNames(fixture, recursive: false)
    let nameBytes = names.map { Data($0.utf8) }
    #expect(nameBytes.contains(Data(existingNFDName.utf8)))
    #expect(nameBytes.contains(Data(newNFCName.utf8)))
    #expect(!nameBytes.contains(Data(existingNFCName.utf8)))
}

@Test func realSVNCommitIntoVersionedNFDDirectoryLeavesWorkingCopyClean() async throws {
    let fixture = try UnicodeCommitFixture()
    defer { fixture.remove() }
    let nfcDirectory = "기존폴더"
    let nfdDirectory = nfcDirectory.decomposedStringWithCanonicalMapping
    let directoryPath = fixture.workingCopy.path + "/" + nfdDirectory
    try createUnicodeIntegrationDirectory(atPath: directoryPath)
    try writeUnicodeIntegrationFile(Data("seed".utf8), atPath: directoryPath + "/seed.txt")
    _ = try runUnicodeIntegrationCommand(fixture.svnPath, ["add", directoryPath])
    _ = try runUnicodeIntegrationCommand(
        fixture.svnPath,
        ["commit", directoryPath, "-m", "existing NFD dir"]
    )

    let nfcChild = "새파일.txt"
    let nfdChild = nfcChild.decomposedStringWithCanonicalMapping
    try writeUnicodeIntegrationFile(
        Data("new".utf8),
        atPath: directoryPath + "/" + nfdChild
    )

    _ = try await fixture.client.commit(
        at: fixture.workingCopy.path,
        paths: [nfdDirectory + "/" + nfdChild],
        message: "new child in versioned NFD dir"
    )

    let names = try repositoryNames(fixture, recursive: true)
    let bytes = names.map { Data($0.utf8) }
    #expect(bytes.contains(Data("\(nfdDirectory)/".utf8)))
    #expect(!bytes.contains(Data("\(nfcDirectory)/".utf8)))
    #expect(bytes.contains(Data("\(nfdDirectory)/\(nfcChild)".utf8)))

    let onDisk = try FileManager.default.contentsOfDirectory(atPath: fixture.workingCopy.path)
        .filter { $0 != ".svn" }
    #expect(onDisk.map { Data($0.utf8) } == [Data(nfdDirectory.utf8)])
    let status = try runUnicodeIntegrationCommand(
        fixture.svnPath,
        ["status", fixture.workingCopy.path]
    )
    #expect(status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

/// `.gitignore`의 NFC 한글 패턴을 그대로 기록하면 svn은 NFD 이름을 무시하지 못합니다.
@Test func realSVNIgnoreRuleMatchesDecomposedDirectoryNameOnDisk() async throws {
    let fixture = try UnicodeCommitFixture()
    defer { fixture.remove() }

    let decomposedName = "임시".decomposedStringWithCanonicalMapping
    let precomposedName = "임시".precomposedStringWithCanonicalMapping
    try createUnicodeIntegrationDirectory(
        atPath: fixture.workingCopy.path + "/" + decomposedName
    )

    let before = try await fixture.client.status(at: fixture.workingCopy.path)
    #expect(before.contains { $0.item == .unversioned })

    // 편집기가 NFC로 저장한 `.gitignore` 패턴을 그대로 넘깁니다.
    try await fixture.client.addIgnoreRule(
        at: fixture.workingCopy.path,
        directory: ".",
        pattern: precomposedName
    )

    let storedPattern = try runUnicodeIntegrationCommand(
        fixture.svnPath,
        ["propget", "svn:ignore", fixture.workingCopy.path]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(Data(storedPattern.utf8) == Data(decomposedName.utf8))

    let after = try await fixture.client.status(at: fixture.workingCopy.path)
    #expect(!after.contains { $0.item == .unversioned })
}

private struct UnicodeCommitFixture {
    let root: URL
    let repository: URL
    let workingCopy: URL
    let repositoryURL: String
    let svnPath: String
    let client: SVNClient

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(firstUnicodeExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(firstUnicodeExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-unicode-commit-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("wc", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try runUnicodeIntegrationCommand(svnadminPath, ["create", repository.path])
        let baseURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        repositoryURL = baseURL + "trunk"
        _ = try runUnicodeIntegrationCommand(svnPath, ["mkdir", repositoryURL, "-m", "initial"])
        _ = try runUnicodeIntegrationCommand(svnPath, ["checkout", repositoryURL, workingCopy.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func repositoryNames(_ fixture: UnicodeCommitFixture, recursive: Bool) throws -> [String] {
    var arguments = ["ls"]
    if recursive { arguments.append("--recursive") }
    arguments.append(fixture.repositoryURL)
    return try runUnicodeIntegrationCommand(fixture.svnPath, arguments)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
}

private func firstUnicodeExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

private func createUnicodeIntegrationDirectory(atPath path: String) throws {
    guard path.withCString({ Darwin.mkdir($0, 0o755) }) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func writeUnicodeIntegrationFile(_ data: Data, atPath path: String) throws {
    let descriptor = path.withCString {
        Darwin.open($0, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { Darwin.close(descriptor) }
    try data.withUnsafeBytes { bytes in
        guard let address = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, address.advanced(by: offset), bytes.count - offset)
            guard count > 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            offset += count
        }
    }
}

@discardableResult
private func runUnicodeIntegrationCommand(
    _ executable: String,
    _ arguments: [String],
    at directory: URL? = nil
) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw UnicodeIntegrationCommandError(
            executable: executable,
            arguments: arguments,
            output: String(decoding: outputData, as: UTF8.self),
            error: String(decoding: errorData, as: UTF8.self)
        )
    }
    return String(decoding: outputData, as: UTF8.self)
}

private struct UnicodeIntegrationCommandError: Error, CustomStringConvertible {
    let executable: String
    let arguments: [String]
    let output: String
    let error: String

    var description: String {
        "Command failed: \(([executable] + arguments).joined(separator: " "))\n\(output)\n\(error)"
    }
}
