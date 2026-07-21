import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func buildsSortedTreeAndExcludesSVNMetadata() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-tree-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".svn"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: root.appendingPathComponent("README.md").path, contents: Data())
    FileManager.default.createFile(atPath: root.appendingPathComponent("Documents/plan.pptx").path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root) }

    let entries = [
        SVNWorkingCopyEntry(path: "Documents", status: "normal", revision: "1"),
        SVNWorkingCopyEntry(path: "Documents/plan.pptx", status: "normal", revision: "1"),
        SVNWorkingCopyEntry(path: "README.md", status: "modified", revision: "1"),
    ]
    let nodes = try await WorkingCopyFileService().tree(at: root.path, svnEntries: entries)

    #expect(nodes.map(\.name) == ["Documents", "README.md"])
    #expect(nodes.first?.children?.map(\.relativePath) == ["Documents/plan.pptx"])
    #expect(nodes.first?.children?.first?.isVersioned == true)
    #expect(nodes.first?.children?.first?.isRegularFile == true)
    #expect(nodes.last?.isRegularFile == true)
    #expect(!nodes.contains { $0.name == ".svn" })
}

@Test func doesNotRecurseIntoSymbolicLinks() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-link-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("Folder/loop"),
        withDestinationURL: root
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let nodes = try await WorkingCopyFileService().tree(at: root.path, svnEntries: [])
    let link = nodes.first?.children?.first
    #expect(link?.isSymbolicLink == true)
    #expect(link?.isRegularFile == false)
    #expect(link?.children == nil)
}

@Test func matchesCanonicalAliasEntriesByRawPathBytes() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-alias-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let composed = "주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    FileManager.default.createFile(atPath: root.path + "/" + decomposed, contents: Data())
    let entries = [
        SVNWorkingCopyEntry(path: decomposed, status: "unversioned"),
        SVNWorkingCopyEntry(path: composed, status: "missing", revision: "7"),
    ]

    let nodes = try await WorkingCopyFileService().tree(at: root.path, svnEntries: entries)
    let entry = try #require(nodes.first?.svnEntry)

    #expect(Data(entry.path.utf8) == Data(decomposed.utf8))
    #expect(entry.status == "unversioned")
}

@Test func canonicalAliasNodeMatchesRepositoryLockPathInsteadOfLocalAlias() {
    let repositoryPath = "주간보고서.hwp"
    let localPath = repositoryPath.decomposedStringWithCanonicalMapping
    let node = WorkingCopyFileNode(
        name: localPath,
        relativePath: localPath,
        isDirectory: false,
        isSymbolicLink: false,
        isRegularFile: true,
        svnEntry: SVNWorkingCopyEntry(
            path: localPath,
            status: "normal",
            revision: "7",
            repositoryPath: repositoryPath
        ),
        children: nil
    )

    #expect(node.matchesRepositoryPath(repositoryPath))
    #expect(!node.matchesRepositoryPath(localPath))
}
