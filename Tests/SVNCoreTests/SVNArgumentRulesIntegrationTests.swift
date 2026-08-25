import Darwin
import Foundation
import Testing
@testable import SVNCore

@Test func realSVNRejectsEmptyCommitSelectionWithoutCommittingWorkingCopy() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("base", to: "tracked.txt")
    try fixture.addAndCommit("seed")
    try fixture.write("changed", to: "tracked.txt")
    let revisionBefore = try fixture.youngestRevision()

    await #expect(throws: SVNClientArgumentError.self) {
        try await fixture.client.commit(
            at: fixture.workingCopyPath,
            paths: [],
            message: "empty selection"
        )
    }

    #expect(try fixture.youngestRevision() == revisionBefore)
    #expect(try fixture.svn(["status"], at: fixture.workingCopyPath).contains("M       tracked.txt"))
}

@Test func realSVNCommitPreservesNFCMessageBytesAndAcceptsLargeMessage() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("base", to: "tracked.txt")
    try fixture.addAndCommit("seed")
    try fixture.write("first", to: "tracked.txt")
    let message = "결산 자료 반영"

    _ = try await fixture.client.commit(
        at: fixture.workingCopyPath,
        paths: ["tracked.txt"],
        message: message
    )

    #expect(try fixture.latestLogMessageBytes() == Data(message.utf8))

    try fixture.write("second", to: "tracked.txt")
    _ = try await fixture.client.commit(
        at: fixture.workingCopyPath,
        paths: ["tracked.txt"],
        message: String(repeating: "가", count: 400_000)
    )
}

@Test func commitRejectsNULMessageWithoutTerminatingCaller() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("base", to: "tracked.txt")
    try fixture.addAndCommit("seed")
    try fixture.write("changed", to: "tracked.txt")

    await #expect(throws: SVNClientArgumentError.self) {
        try await fixture.client.commit(
            at: fixture.workingCopyPath,
            paths: ["tracked.txt"],
            message: "정산\0완료"
        )
    }

    #expect(try fixture.svn(["status"], at: fixture.workingCopyPath).contains("M       tracked.txt"))
}

@Test func realSVNExportEscapesDestinationPegSyntax() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("asset", to: "asset.png")
    try fixture.addAndCommit("seed")
    let destinationPath = fixture.rootPath + "/icon@2x.png"

    _ = try await fixture.client.export(
        at: fixture.workingCopyPath,
        relativePath: "asset.png",
        revision: "2",
        destinationPath: destinationPath
    )

    #expect(try Data(contentsOf: URL(fileURLWithPath: destinationPath)) == Data("asset".utf8))
    #expect(!FileManager.default.fileExists(atPath: destinationPath + "@"))
}

@Test func realSVNMoveKeepsAtSignAndNormalizesNewNameToNFC() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("at", to: "at-source.txt")
    try fixture.write("nfd", to: "nfd-source.txt")
    try fixture.addAndCommit("seed")
    let nfdDestination = "기-이동.txt"
    let nfcDestination = nfdDestination.precomposedStringWithCanonicalMapping

    _ = try await fixture.client.move(
        at: fixture.workingCopyPath,
        sourceRelativePath: "at-source.txt",
        destinationRelativePath: "image@2x.png"
    )
    _ = try await fixture.client.move(
        at: fixture.workingCopyPath,
        sourceRelativePath: "nfd-source.txt",
        destinationRelativePath: nfdDestination
    )

    let entryBytes = try fixture.workingCopyEntryBytes()
    #expect(entryBytes.contains(Data("image@2x.png".utf8)))
    #expect(!entryBytes.contains(Data("image@2x.png@".utf8)))
    #expect(entryBytes.contains(Data(nfcDestination.utf8)))
    #expect(!entryBytes.contains(Data(nfdDestination.utf8)))
}

@Test func realSVNCopyNormalizesNewNameToNFC() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("copy", to: "source.txt")
    try fixture.addAndCommit("seed")
    let nfdDestination = "기-복사.txt"
    let nfcDestination = nfdDestination.precomposedStringWithCanonicalMapping

    _ = try await fixture.client.copy(
        at: fixture.workingCopyPath,
        sourceRelativePath: "source.txt",
        destinationRelativePath: nfdDestination
    )

    let entryBytes = try fixture.workingCopyEntryBytes()
    #expect(entryBytes.contains(Data(nfcDestination.utf8)))
    #expect(!entryBytes.contains(Data(nfdDestination.utf8)))
}

@Test func realSVNRepositoryMoveKeepsDestinationAtSignLiteral() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    let nfdName = "기@원본.txt"
    let nfcName = nfdName.precomposedStringWithCanonicalMapping
    try fixture.writeRaw("repository move", to: nfdName)
    try fixture.addAndCommit("seed")
    let entriesBefore = try fixture.svn(["list", fixture.trunkURL])
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    #expect(entriesBefore.contains { Data($0.utf8) == Data(nfdName.utf8) })

    let message = "경로 정규화"
    _ = try await fixture.client.normalizeRepositoryPaths(
        [SVNRepositoryPathNormalizationTarget(
            repositoryPath: nfdName,
            normalizedPath: nfcName,
            isDirectory: false
        )],
        at: fixture.workingCopyPath,
        message: message
    )

    let entries = try fixture.svn(["list", fixture.trunkURL])
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    #expect(entries.contains { Data($0.utf8) == Data(nfcName.utf8) })
    #expect(!entries.contains { Data($0.utf8) == Data((nfcName + "@").utf8) })
    let logXML = try fixture.svn(["log", "--xml", "--limit", "1", fixture.trunkURL])
    #expect(messageBytes(in: logXML) == Data(message.utf8))
}

@Test func realSVNCheckoutAndVerifyEscapeAtSignRepositoryURL() async throws {
    let fixture = try StandaloneSVNRepository(name: "repository@team")
    defer { fixture.remove() }
    let checkoutPath = fixture.rootPath + "/checkout"

    _ = try await fixture.client.checkout(
        repositoryURL: fixture.repositoryURL,
        destinationPath: checkoutPath
    )
    let secondCheckoutPath = fixture.rootPath + "/checkout-explicit-failures"
    _ = try await fixture.client.checkout(
        repositoryURL: fixture.repositoryURL,
        destinationPath: secondCheckoutPath,
        allowedServerCertificateFailures: []
    )
    try await fixture.client.verifyCredentials(at: checkoutPath)

    #expect(try fixture.svn(["info", "--show-item", "url"], at: checkoutPath)
        .trimmingCharacters(in: .whitespacesAndNewlines) == fixture.repositoryURL)
}

@Test func realSVNCheckoutPreservesRawNFDRepositoryURL() async throws {
    let nfdName = "기-저장소"
    let fixture = try StandaloneSVNRepository(name: "repository")
    defer { fixture.remove() }
    let checkoutPath = fixture.rootPath + "/checkout"
    let nfdRepositoryURL = fixture.repositoryURL + "/" + nfdName
    let encodedNFDName = nfdName.utf8.map { String(format: "%%%02X", $0) }.joined()
    _ = try fixture.svn(
        ["mkdir", fixture.repositoryURL + "/" + encodedNFDName, "-m", "NFD path"],
        at: fixture.rootPath
    )

    _ = try await fixture.client.checkout(
        repositoryURL: nfdRepositoryURL,
        destinationPath: checkoutPath
    )

    #expect(FileManager.default.fileExists(atPath: checkoutPath + "/.svn"))
}

@Test func realSVNUsesRequestedPegForDeletedHistoryAndEscapesPercentDiffPath() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("old", to: "old/deleted.txt")
    try fixture.addAndCommit("historical source")
    let historicalRevision = try fixture.youngestRevision()
    try fixture.svn(["delete", "old"], at: fixture.workingCopyPath)
    try fixture.commit("delete source")

    let entries = try await fixture.client.repositoryEntries(
        at: fixture.trunkURL + "/old",
        revision: historicalRevision
    )
    #expect(entries.map(\.name) == ["deleted.txt"])

    let nfdRestoreName = "기-복원.txt"
    let nfcRestoreName = nfdRestoreName.precomposedStringWithCanonicalMapping
    _ = try await fixture.client.copy(
        repositoryURL: fixture.trunkURL + "/old/deleted.txt",
        revision: historicalRevision,
        to: nfdRestoreName,
        at: fixture.workingCopyPath
    )
    #expect(try Data(contentsOf: URL(fileURLWithPath: fixture.workingCopyPath + "/" + nfcRestoreName)) == Data("old".utf8))
    let restoreEntryBytes = try fixture.workingCopyEntryBytes()
    #expect(restoreEntryBytes.contains(Data(nfcRestoreName.utf8)))
    #expect(!restoreEntryBytes.contains(Data(nfdRestoreName.utf8)))

    try fixture.write("one", to: "report%2010.txt")
    try fixture.svn(["add", "report%2010.txt"], at: fixture.workingCopyPath)
    try fixture.commit("percent one")
    try fixture.write("two", to: "report%2010.txt")
    try fixture.commit("percent two")
    let revision = try fixture.youngestRevision()
    let diff = try await fixture.client.revisionDiff(
        at: fixture.workingCopyPath,
        revision: revision,
        repositoryPath: "/trunk/report%2010.txt",
        workingCopyRepositoryPath: "/trunk",
        pegRevision: revision
    )
    #expect(diff.contains("-one"))
    #expect(diff.contains("+two"))
}

@Test func realSVNRelocatesRegisteredSubdirectoryFromWorkingCopyRoot() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("child", to: "registered/file.txt")
    try fixture.addAndCommit("seed")
    let movedRepositoryPath = fixture.rootPath + "/repository@new"
    try FileManager.default.moveItem(
        atPath: fixture.repositoryPath,
        toPath: movedRepositoryPath
    )
    let oldProjectURL = fixture.trunkURL + "/registered"
    let newProjectURL = "file://" + movedRepositoryPath + "/trunk/registered"

    _ = try await fixture.client.relocate(
        at: fixture.workingCopyPath + "/registered",
        fromRepositoryURL: oldProjectURL,
        toRepositoryURL: newProjectURL
    )

    let actualURL = try fixture.svn(
        ["info", "--show-item", "url"],
        at: fixture.workingCopyPath + "/registered"
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(actualURL == newProjectURL)
}

@Test func relocatePlacesArgumentTerminatorBeforeUnmodifiedURLPrefixes() async throws {
    let rootPath = FileManager.default.temporaryDirectory.path
        + "/svn-relocate-arguments-\(UUID().uuidString)"
    let registeredPath = rootPath + "/registered"
    try FileManager.default.createDirectory(
        atPath: rootPath + "/.svn",
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(atPath: registeredPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: rootPath) }
    let executablePath = rootPath + "/fake-svn"
    let script = """
    #!/bin/sh
    case " $* " in
      *" --show-item kind "*) printf 'dir\\n'; exit 0 ;;
      *" --show-item url "*)
        case "$PWD" in
          */registered) printf 'file:///old/root/registered\\n' ;;
          *) printf 'file:///old/root\\n' ;;
        esac
        exit 0
        ;;
    esac
    found=false
    for argument in "$@"
    do
      if [ "$found" = true ]; then printf '[%s]\\n' "$argument"; fi
      if [ "$argument" = relocate ]; then found=true; fi
    done
    """
    try Data(script.utf8).write(to: URL(fileURLWithPath: executablePath))
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: executablePath
    )
    let client = SVNClient(
        executablePath: executablePath,
        configDirectoryPath: rootPath + "/svn-config"
    )

    let result = try await client.relocate(
        at: registeredPath,
        fromRepositoryURL: "file:///old/root/registered",
        toRepositoryURL: "file:///new/root/registered"
    )

    #expect(result == "[--]\n[file:///old/root]\n[file:///new/root]\n[.]\n")
}

@Test func emptyPathAndLeadingHyphenPropertyNameAreRejectedBeforeSVNLaunch() async throws {
    let fixture = try SVNArgumentFixture()
    defer { fixture.remove() }
    try fixture.write("base", to: "tracked.txt")
    try fixture.addAndCommit("seed")
    try fixture.write("changed", to: "tracked.txt")

    await #expect(throws: SVNError.self) {
        try await fixture.client.revert(at: fixture.workingCopyPath, relativePath: "")
    }
    #expect(try fixture.svn(["status"], at: fixture.workingCopyPath).contains("M       tracked.txt"))

    await #expect(throws: SVNClientArgumentError.self) {
        try await fixture.client.setProperty(
            named: "-custom",
            value: Data("value".utf8),
            at: fixture.workingCopyPath,
            relativePath: "tracked.txt"
        )
    }
    await #expect(throws: SVNClientArgumentError.self) {
        try await fixture.client.propertyValue(
            named: "-custom",
            at: fixture.workingCopyPath,
            relativePath: "tracked.txt"
        )
    }
    await #expect(throws: SVNClientArgumentError.self) {
        try await fixture.client.deleteProperty(
            named: "-custom",
            at: fixture.workingCopyPath,
            relativePath: "tracked.txt"
        )
    }
}

private final class SVNArgumentFixture {
    let rootPath: String
    let repositoryPath: String
    let workingCopyPath: String
    let trunkURL: String
    let svnPath: String
    let svnadminPath: String
    let svnlookPath: String
    let client: SVNClient

    init() throws {
        svnPath = try #require(Self.executable(["/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn"]))
        svnadminPath = try #require(Self.executable(["/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin"]))
        svnlookPath = try #require(Self.executable(["/opt/homebrew/bin/svnlook", "/usr/local/bin/svnlook", "/usr/bin/svnlook"]))
        rootPath = FileManager.default.temporaryDirectory.path + "/svn-argument-rules-\(UUID().uuidString)"
        repositoryPath = rootPath + "/repository"
        workingCopyPath = rootPath + "/working-copy"
        try FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repositoryPath])
        trunkURL = "file://" + repositoryPath + "/trunk"
        _ = try Self.run(svnPath, ["mkdir", trunkURL, "-m", "create trunk"])
        _ = try Self.run(svnPath, ["checkout", trunkURL, workingCopyPath])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: rootPath + "/svn-config"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: rootPath)
    }

    func write(_ contents: String, to relativePath: String) throws {
        let path = workingCopyPath + "/" + relativePath
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
    }

    func writeRaw(_ contents: String, to relativePath: String) throws {
        let path = workingCopyPath + "/" + relativePath
        let descriptor = path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        let data = Data(contents.utf8)
        let written = data.withUnsafeBytes { bytes in
            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
        guard written == data.count else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    func addAndCommit(_ message: String) throws {
        _ = try svn(["add", "--force", "."], at: workingCopyPath)
        try commit(message)
    }

    func commit(_ message: String) throws {
        _ = try svn(["commit", "-m", message], at: workingCopyPath)
    }

    func youngestRevision() throws -> String {
        try Self.run(svnlookPath, ["youngest", repositoryPath])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func latestLogMessageBytes() throws -> Data {
        var data = try Self.runData(svnlookPath, ["log", repositoryPath])
        while data.last == 0x0A || data.last == 0x0D { data.removeLast() }
        return data
    }

    func workingCopyEntryBytes() throws -> [Data] {
        try FileManager.default.contentsOfDirectory(atPath: workingCopyPath).map { Data($0.utf8) }
    }

    @discardableResult
    func svn(_ arguments: [String], at path: String? = nil) throws -> String {
        try Self.run(svnPath, arguments, at: path)
    }

    private static func executable(_ candidates: [String]) -> String? {
        candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    fileprivate static func run(_ executable: String, _ arguments: [String], at path: String? = nil) throws -> String {
        String(decoding: try runData(executable, arguments, at: path), as: UTF8.self)
    }

    private static func runData(_ executable: String, _ arguments: [String], at path: String? = nil) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw SVNArgumentProcessError(
                command: ([executable] + arguments).joined(separator: " "),
                detail: String(decoding: errorData, as: UTF8.self)
            )
        }
        return outputData
    }
}

private final class StandaloneSVNRepository {
    let rootPath: String
    let repositoryURL: String
    let client: SVNClient
    private let svnPath: String

    init(name: String) throws {
        svnPath = try #require(["/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn"]
            .first(where: FileManager.default.isExecutableFile(atPath:)))
        let svnadminPath = try #require(["/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin"]
            .first(where: FileManager.default.isExecutableFile(atPath:)))
        rootPath = FileManager.default.temporaryDirectory.path + "/svn-standalone-\(UUID().uuidString)"
        let repositoryPath = rootPath + "/" + name
        try FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true)
        _ = try SVNArgumentFixture.run(svnadminPath, ["create", repositoryPath])
        repositoryURL = "file://" + repositoryPath
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: rootPath + "/svn-config"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: rootPath)
    }

    func svn(_ arguments: [String], at path: String) throws -> String {
        try SVNArgumentFixture.run(svnPath, arguments, at: path)
    }
}

private struct SVNArgumentProcessError: Error, CustomStringConvertible {
    let command: String
    let detail: String
    var description: String { "\(command)\n\(detail)" }
}

private func messageBytes(in logXML: String) -> Data? {
    guard let start = logXML.range(of: "<msg>"),
          let end = logXML.range(of: "</msg>", range: start.upperBound..<logXML.endIndex) else {
        return nil
    }
    return Data(logXML[start.upperBound..<end.lowerBound].utf8)
}
