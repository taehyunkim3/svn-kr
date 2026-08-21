import Foundation
import Darwin
import Testing
@testable import SVNCore

@Test func pathNormalizationRenamesNFDFileToNFCBytes() throws {
    let fixture = try makeNormalizationFixture()
    defer { try? FileManager.default.removeItem(at: fixture) }
    let nfcName = "한글파일.txt"
    let nfdName = nfcName.decomposedStringWithCanonicalMapping
    try writeNormalizationFile(Data("content".utf8), atPath: fixture.path + "/" + nfdName)

    let result = SVNPathNormalization.normalizeNewPaths(
        rootPath: fixture.path,
        relativePaths: [nfdName]
    )

    #expect(result.didRename)
    #expect(result.unnormalizedPaths.isEmpty)
    #expect(result.normalizedPaths.map { Data($0.utf8) } == [Data(nfcName.utf8)])
    #expect(try storedNames(in: fixture).map { Data($0.utf8) } == [Data(nfcName.utf8)])
}

@Test func pathNormalizationRecursivelyRenamesNFDDirectoryAndChild() throws {
    let fixture = try makeNormalizationFixture()
    defer { try? FileManager.default.removeItem(at: fixture) }
    let nfcDirectory = "한글폴더"
    let nfdDirectory = nfcDirectory.decomposedStringWithCanonicalMapping
    let nfcFile = "하위파일.txt"
    let nfdFile = nfcFile.decomposedStringWithCanonicalMapping
    try createNormalizationDirectory(atPath: fixture.path + "/" + nfdDirectory)
    try writeNormalizationFile(
        Data("nested".utf8),
        atPath: fixture.path + "/" + nfdDirectory + "/" + nfdFile
    )

    let result = SVNPathNormalization.normalizeNewPaths(
        rootPath: fixture.path,
        relativePaths: [nfdDirectory]
    )

    #expect(result.didRename)
    #expect(result.unnormalizedPaths.isEmpty)
    let rootNames = try storedNames(in: fixture)
    #expect(rootNames.map { Data($0.utf8) } == [Data(nfcDirectory.utf8)])
    let normalizedDirectoryURL = fixture.appendingPathComponent(nfcDirectory, isDirectory: true)
    #expect(try storedNames(in: normalizedDirectoryURL).map { Data($0.utf8) } == [Data(nfcFile.utf8)])
}

@Test func pathNormalizationLeavesNFCPathUntouched() throws {
    let fixture = try makeNormalizationFixture()
    defer { try? FileManager.default.removeItem(at: fixture) }
    let nfcName = "이미한글.txt"
    try writeNormalizationFile(Data("same".utf8), atPath: fixture.path + "/" + nfcName)

    let result = SVNPathNormalization.normalizeNewPaths(
        rootPath: fixture.path,
        relativePaths: [nfcName]
    )

    #expect(!result.didRename)
    #expect(result.unnormalizedPaths.isEmpty)
    #expect(Data(result.normalizedPaths[0].utf8) == Data(nfcName.utf8))
    #expect(try storedNames(in: fixture).map { Data($0.utf8) } == [Data(nfcName.utf8)])
}

@Test func pathNormalizationReportsExistingDistinctNFCTarget() {
    let nfcName = "충돌.txt"
    let nfdName = nfcName.decomposedStringWithCanonicalMapping
    let fileManager = CollisionDirectoryFileManager(entries: [nfdName, nfcName])

    let result = SVNPathNormalization.normalizeNewPaths(
        rootPath: "/virtual-normalization-root",
        relativePaths: [nfdName],
        fileManager: fileManager
    )

    #expect(!result.didRename)
    #expect(result.normalizedPaths.map { Data($0.utf8) } == [Data(nfdName.utf8)])
    #expect(result.unnormalizedPaths.map { Data($0.utf8) } == [Data(nfdName.utf8)])
}

private func makeNormalizationFixture() throws -> URL {
    let fixture = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-path-normalization-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    return fixture
}

private func storedNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .sorted { Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8)) }
}

private func createNormalizationDirectory(atPath path: String) throws {
    guard path.withCString({ Darwin.mkdir($0, 0o755) }) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func writeNormalizationFile(_ data: Data, atPath path: String) throws {
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

private final class CollisionDirectoryFileManager: FileManager, @unchecked Sendable {
    let entries: [String]

    init(entries: [String]) {
        self.entries = entries
        super.init()
    }

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        entries
    }
}
