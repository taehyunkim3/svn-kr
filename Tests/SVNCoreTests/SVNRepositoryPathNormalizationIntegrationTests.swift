import Darwin
import Foundation
import Testing
@testable import SVNCore

@Test func realSVNNormalizesMinimalRepositoryPathSetAndUpdateCleansWorkingCopy() async throws {
    let fixture = try RepositoryNormalizationFixture()
    defer { fixture.remove() }
    let nfcFile = "루트파일.txt"
    let nfdFile = nfcFile.decomposedStringWithCanonicalMapping
    let nfcDirectory = "한글폴더"
    let nfdDirectory = nfcDirectory.decomposedStringWithCanonicalMapping
    let nfcChild = "하위파일.txt"

    try writeRepositoryNormalizationFile(
        Data("root".utf8),
        atPath: fixture.workingCopy.path + "/" + nfdFile
    )
    try createRepositoryNormalizationDirectory(
        atPath: fixture.workingCopy.path + "/" + nfdDirectory
    )
    try writeRepositoryNormalizationFile(
        Data("child".utf8),
        atPath: fixture.workingCopy.path + "/" + nfdDirectory + "/" + nfcChild
    )
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["add", "--force", fixture.workingCopy.path]
    )
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["commit", fixture.workingCopy.path, "-m", "NFD seed"]
    )

    let targets = try await fixture.client.repositoryPathsNeedingNormalization(
        at: fixture.workingCopy.path
    )
    #expect(targets.count == 2)
    #expect(targets.allSatisfy { $0.repositoryPath.split(separator: "/").count == 1 })
    #expect(targets.contains { Data($0.repositoryPath.utf8) == Data(nfdFile.utf8) })
    #expect(targets.contains { Data($0.repositoryPath.utf8) == Data(nfdDirectory.utf8) })
    #expect(!targets.contains {
        Data($0.repositoryPath.utf8) == Data((nfdDirectory + "/" + nfcChild).utf8)
    })

    let revisionBefore = try fixture.repositoryRevision()
    let result = try await fixture.client.normalizeRepositoryPaths(
        targets,
        at: fixture.workingCopy.path,
        message: "저장소 경로 NFC 정규화"
    )
    let revisionAfter = try fixture.repositoryRevision()

    #expect(result.renamedTargets == targets)
    #expect(result.skippedTargets.isEmpty)
    #expect(result.committedRevisions.count == 2)
    #expect(revisionAfter - revisionBefore == 2)

    let repositoryPaths = try fixture.repositoryPaths()
    #expect(repositoryPaths.allSatisfy {
        Data($0.utf8) == Data($0.precomposedStringWithCanonicalMapping.utf8)
    })
    #expect(repositoryPaths.map { Data($0.utf8) }.contains(Data(nfcFile.utf8)))
    #expect(repositoryPaths.map { Data($0.utf8) }.contains(Data((nfcDirectory + "/" + nfcChild).utf8)))

    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["update", fixture.workingCopy.path]
    )
    let status = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["status", fixture.workingCopy.path]
    )
    #expect(status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func realSVNRejectsRepositoryNormalizationWhenTargetTreeHasLocalChanges() async throws {
    let fixture = try RepositoryNormalizationFixture()
    defer { fixture.remove() }
    let directory = "변경폴더".decomposedStringWithCanonicalMapping
    let child = "tracked.txt"
    let childPath = fixture.workingCopy.path + "/" + directory + "/" + child

    try createRepositoryNormalizationDirectory(
        atPath: fixture.workingCopy.path + "/" + directory
    )
    try writeRepositoryNormalizationFile(Data("base".utf8), atPath: childPath)
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["add", "--force", fixture.workingCopy.path]
    )
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["commit", fixture.workingCopy.path, "-m", "NFD seed"]
    )
    try writeRepositoryNormalizationFile(Data("modified".utf8), atPath: childPath)

    let targets = try await fixture.client.repositoryPathsNeedingNormalization(
        at: fixture.workingCopy.path
    )
    do {
        _ = try await fixture.client.normalizeRepositoryPaths(
            targets,
            at: fixture.workingCopy.path,
            message: "must not commit"
        )
        Issue.record("Expected local-change precondition failure")
    } catch let SVNRepositoryPathNormalizationError.blockedByLocalChanges(paths) {
        #expect(paths.contains { Data($0.utf8) == Data((directory + "/" + child).utf8) })
    }

    let remaining = try fixture.repositoryPaths()
    #expect(remaining.contains { Data($0.utf8) == Data(directory.utf8) })
}

@Test func realSVNSkipsRepositoryNormalizationWhenNFCPathAlreadyExists() async throws {
    let fixture = try RepositoryNormalizationFixture()
    defer { fixture.remove() }
    let nfc = "충돌폴더"
    let nfd = nfc.decomposedStringWithCanonicalMapping

    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["mkdir", fixture.encodedRepositoryURL(appending: nfd), "-m", "NFD directory"]
    )
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["mkdir", fixture.encodedRepositoryURL(appending: nfc), "-m", "NFC directory"]
    )

    let targets = try await fixture.client.repositoryPathsNeedingNormalization(
        at: fixture.workingCopy.path
    )
    let target = try #require(targets.first)
    let revisionBefore = try fixture.repositoryRevision()
    let result = try await fixture.client.normalizeRepositoryPaths(
        targets,
        at: fixture.workingCopy.path,
        message: "collision skip"
    )

    #expect(result.renamedTargets.isEmpty)
    #expect(result.skippedTargets == [target])
    #expect(result.committedRevisions.isEmpty)
    #expect(try fixture.repositoryRevision() == revisionBefore)
}

@Test func realSVNRejectsRepositoryNormalizationWhenTargetIsLocked() async throws {
    let fixture = try RepositoryNormalizationFixture()
    defer { fixture.remove() }
    let file = "잠금파일.txt".decomposedStringWithCanonicalMapping
    let localPath = fixture.workingCopy.path + "/" + file

    try writeRepositoryNormalizationFile(Data("locked".utf8), atPath: localPath)
    _ = try runRepositoryNormalizationCommand(fixture.svnPath, ["add", localPath])
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["commit", localPath, "-m", "NFD seed"]
    )
    _ = try runRepositoryNormalizationCommand(
        fixture.svnPath,
        ["lock", localPath, "-m", "editing"]
    )

    let targets = try await fixture.client.repositoryPathsNeedingNormalization(
        at: fixture.workingCopy.path
    )
    do {
        _ = try await fixture.client.normalizeRepositoryPaths(
            targets,
            at: fixture.workingCopy.path,
            message: "must not commit"
        )
        Issue.record("Expected lock precondition failure")
    } catch let SVNRepositoryPathNormalizationError.blockedByLocks(paths) {
        #expect(paths.contains { Data($0.utf8) == Data(file.utf8) })
    }
}

private struct RepositoryNormalizationFixture {
    let root: URL
    let repository: URL
    let workingCopy: URL
    let repositoryURL: String
    let svnPath: String
    let client: SVNClient

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(repositoryNormalizationExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(repositoryNormalizationExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = fileManager.temporaryDirectory
            .appendingPathComponent("svn-repository-normalization-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("wc", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try runRepositoryNormalizationCommand(svnadminPath, ["create", repository.path])
        let baseURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        repositoryURL = baseURL + "trunk"
        _ = try runRepositoryNormalizationCommand(svnPath, ["mkdir", repositoryURL, "-m", "initial"])
        _ = try runRepositoryNormalizationCommand(
            svnPath,
            ["checkout", repositoryURL, workingCopy.path]
        )
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func repositoryPaths() throws -> [String] {
        try runRepositoryNormalizationCommand(svnPath, ["ls", "--recursive", repositoryURL])
            .split(whereSeparator: \.isNewline)
            .map { line in
                let value = String(line)
                return value.hasSuffix("/") ? String(value.dropLast()) : value
            }
    }

    func repositoryRevision() throws -> Int {
        let output = try runRepositoryNormalizationCommand(
            svnPath,
            ["info", "--show-item", "revision", repositoryURL]
        )
        return try #require(Int(output.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func encodedRepositoryURL(appending path: String) -> String {
        SVNRepositoryPathNormalization.repositoryURL(repositoryURL, appending: path)
    }
}

private func repositoryNormalizationExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

private func createRepositoryNormalizationDirectory(atPath path: String) throws {
    guard path.withCString({ Darwin.mkdir($0, 0o755) }) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func writeRepositoryNormalizationFile(_ data: Data, atPath path: String) throws {
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
private func runRepositoryNormalizationCommand(
    _ executable: String,
    _ arguments: [String]
) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw RepositoryNormalizationCommandError(
            executable: executable,
            arguments: arguments,
            output: String(decoding: outputData, as: UTF8.self),
            error: String(decoding: errorData, as: UTF8.self)
        )
    }
    return String(decoding: outputData, as: UTF8.self)
}

private struct RepositoryNormalizationCommandError: Error, CustomStringConvertible {
    let executable: String
    let arguments: [String]
    let output: String
    let error: String

    var description: String {
        "Command failed: \(([executable] + arguments).joined(separator: " "))\n\(output)\n\(error)"
    }
}
