import Foundation
import Testing
@testable import SVNCore

@Suite("SVNWorkingCopySnapshotPropertyTests")
struct SVNWorkingCopySnapshotPropertyTests {
    @Test func preservesPropertyOnlyAndSwitchedEntries() throws {
        let xml = """
        <?xml version="1.0"?><status><target path=".">
          <entry path="."><wc-status item="normal" revision="7" props="none"/></entry>
          <entry path="Documents"><wc-status item="normal" revision="7" props="modified"/></entry>
          <entry path="Sources"><wc-status item="normal" revision="7" props="none" switched="true"/></entry>
        </target></status>
        """

        let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))

        #expect(snapshot.statuses == [
            SVNStatusEntry(
                path: "Documents",
                item: SVNStatusKind(rawValue: "normal"),
                revision: "7",
                propertyState: .modified
            ),
            SVNStatusEntry(
                path: "Sources",
                item: SVNStatusKind(rawValue: "normal"),
                revision: "7",
                isSwitched: true
            ),
        ])
    }

    @Test func aggregatesPropertyConflictAndSwitchAcrossCanonicalGroup() throws {
        let composed = "보고서"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let xml = """
        <?xml version="1.0"?><status><target path=".">
          <entry path="."><wc-status item="normal" revision="7" props="none"/></entry>
          <entry path="\(composed)"><wc-status item="modified" revision="7" props="modified"/></entry>
          <entry path="\(decomposed)"><wc-status item="modified" revision="7" props="conflicted" switched="true"/></entry>
        </target></status>
        """

        let entry = try #require(
            SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8)).statuses.first
        )

        #expect(entry.propertyState == .conflicted)
        #expect(entry.isSwitched)
    }

    @Test func nodeKindAnnotationPreservesPropertyAndSwitchedMetadata() throws {
        let snapshot = SVNWorkingCopySnapshot(
            statuses: [
                SVNStatusEntry(
                    path: "Documents",
                    item: SVNStatusKind(rawValue: "normal"),
                    revision: "7",
                    propertyState: .modified,
                    isSwitched: true
                ),
            ],
            revision: SVNWorkingCopyRevision(minimum: "7", maximum: "7"),
            collisions: [],
            versionedPathsByCanonicalKey: [:]
        )

        let entry = try #require(snapshot.annotatingNodeKinds([
            SVNPathIdentity(rawPath: "Documents"): .directory,
        ]).statuses.first)

        #expect(entry.nodeKind == .directory)
        #expect(entry.propertyState == .modified)
        #expect(entry.isSwitched)
    }
}

@Test func realSVNPreservesPropertyAndSwitchedMetadataThroughSnapshot() throws {
    let fileManager = FileManager.default
    let svnPath = try #require(snapshotPropertyExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(snapshotPropertyExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let fixture = fileManager.temporaryDirectory
        .appendingPathComponent("svn-snapshot-property-\(UUID().uuidString)", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let seed = fixture.appendingPathComponent("seed", isDirectory: true)
    let firstWorkingCopy = fixture.appendingPathComponent("working-copy-one", isDirectory: true)
    let secondWorkingCopy = fixture.appendingPathComponent("working-copy-two", isDirectory: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    _ = try runSnapshotPropertyCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["mkdir", repositoryURL + "trunk", repositoryURL + "branches", "-m", "init"]
    )
    _ = try runSnapshotPropertyCommand(svnPath, ["checkout", repositoryURL + "trunk", seed.path])
    try fileManager.createDirectory(
        at: seed.appendingPathComponent("property-dir"),
        withIntermediateDirectories: false
    )
    try fileManager.createDirectory(
        at: seed.appendingPathComponent("switch-dir"),
        withIntermediateDirectories: false
    )
    _ = try runSnapshotPropertyCommand(svnPath, ["add", seed.appendingPathComponent("property-dir").path])
    _ = try runSnapshotPropertyCommand(svnPath, ["add", seed.appendingPathComponent("switch-dir").path])
    _ = try runSnapshotPropertyCommand(svnPath, ["commit", seed.path, "-m", "structure"])
    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["copy", repositoryURL + "trunk/switch-dir", repositoryURL + "branches/alternate", "-m", "branch"]
    )
    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["checkout", repositoryURL + "trunk", firstWorkingCopy.path]
    )
    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["checkout", repositoryURL + "trunk", secondWorkingCopy.path]
    )

    let firstPropertyDirectory = firstWorkingCopy.appendingPathComponent("property-dir").path
    let secondPropertyDirectory = secondWorkingCopy.appendingPathComponent("property-dir").path
    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["propset", "svn:ignore", "*.first", firstPropertyDirectory]
    )
    let modifiedXML = try snapshotPropertyStatusXML(svnPath, at: firstWorkingCopy.path)
    let modified = try #require(
        SVNXMLParser.workingCopySnapshot(from: Data(modifiedXML.utf8)).statuses.first {
            $0.path == firstPropertyDirectory
        }
    )
    #expect(modifiedXML.contains("props=\"modified\""))
    #expect(modified.propertyState == .modified)

    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["propset", "svn:ignore", "*.second", secondPropertyDirectory]
    )
    _ = try runSnapshotPropertyCommand(svnPath, ["commit", firstPropertyDirectory, "-m", "property"])
    _ = try runSnapshotPropertyCommand(svnPath, ["update", secondWorkingCopy.path])
    let conflictedXML = try snapshotPropertyStatusXML(svnPath, at: secondWorkingCopy.path)
    let conflicted = try #require(
        SVNXMLParser.workingCopySnapshot(from: Data(conflictedXML.utf8)).statuses.first {
            $0.path == secondPropertyDirectory
        }
    )
    #expect(conflictedXML.contains("props=\"conflicted\""))
    #expect(conflicted.propertyState == .conflicted)

    let switchedDirectory = firstWorkingCopy.appendingPathComponent("switch-dir").path
    _ = try runSnapshotPropertyCommand(
        svnPath,
        ["switch", repositoryURL + "branches/alternate", switchedDirectory]
    )
    let switchedXML = try snapshotPropertyStatusXML(svnPath, at: firstWorkingCopy.path)
    let switched = try #require(
        SVNXMLParser.workingCopySnapshot(from: Data(switchedXML.utf8)).statuses.first {
            $0.path == switchedDirectory
        }
    )
    #expect(switchedXML.contains("switched=\"true\""))
    #expect(switched.isSwitched)
}

private func snapshotPropertyStatusXML(_ svnPath: String, at path: String) throws -> String {
    try runSnapshotPropertyCommand(
        svnPath,
        ["status", "--verbose", "--no-ignore", "--xml", path]
    )
}

private func snapshotPropertyExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runSnapshotPropertyCommand(
    _ executable: String,
    _ arguments: [String]
) throws -> String {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw SnapshotPropertyCommandError(
            command: ([executable] + arguments).joined(separator: " "),
            output: output + error
        )
    }
    return output
}

private struct SnapshotPropertyCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String

    var description: String { "\(command): \(output)" }
}
