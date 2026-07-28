import Foundation
import Testing
@testable import SVNCore

@Test func sharedFileComparisonChecksSizeAndContents() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-system-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("first")
    let second = directory.appendingPathComponent("second")
    let bytes = Data(repeating: 0x41, count: 2 * 1024 * 1024 + 17)
    try bytes.write(to: first)
    try bytes.write(to: second)

    #expect(try SVNFileSystem.filesHaveEqualContents(first, second))
    try Data([0x42]).append(to: second)
    #expect(try !SVNFileSystem.filesHaveEqualContents(first, second))
}

@Test func sharedFileOverwriteTruncatesDestination() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-file-overwrite-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    let destination = directory.appendingPathComponent("destination")
    try Data("short".utf8).write(to: source)
    try Data(repeating: 0x58, count: 10_000).write(to: destination)

    try SVNFileSystem.overwriteFile(at: destination, withContentsOf: source)

    #expect(try Data(contentsOf: destination) == Data("short".utf8))
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}
