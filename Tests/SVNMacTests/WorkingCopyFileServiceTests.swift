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

@Test func matchesSingleCanonicalAliasEntryAcrossFilesystemNormalization() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-single-alias-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let repositoryPath = "주간보고서.hwp"
    let localPath = repositoryPath.decomposedStringWithCanonicalMapping
    FileManager.default.createFile(atPath: root.path + "/" + localPath, contents: Data())

    let nodes = try await WorkingCopyFileService().tree(
        at: root.path,
        svnEntries: [
            SVNWorkingCopyEntry(
                path: repositoryPath,
                status: "normal",
                revision: "7",
                repositoryPath: repositoryPath
            ),
        ]
    )
    let node = try #require(nodes.first)

    #expect(Data(node.relativePath.utf8) == Data(localPath.utf8))
    #expect(node.isVersioned)
    #expect(Data(try #require(node.svnEntry).path.utf8) == Data(repositoryPath.utf8))
    #expect(node.matchesRepositoryPath(repositoryPath))
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

@Test func listsOnlyImmediateChildrenAndReportsExpandableDirectories() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-direct-\(UUID().uuidString)", isDirectory: true)
    let empty = root.appendingPathComponent("Empty", isDirectory: true)
    let metadataOnly = root.appendingPathComponent("Metadata Only/.svn", isDirectory: true)
    let populated = root.appendingPathComponent("Populated", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: metadataOnly, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: populated.appendingPathComponent("Grandchild", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("nested".utf8).write(to: populated.appendingPathComponent("Grandchild/file.txt"))
    defer { try? FileManager.default.removeItem(at: root) }

    let nodes = try await WorkingCopyFileService().directoryContents(
        at: root.path,
        relativeDirectory: "",
        svnEntries: []
    )

    #expect(nodes.map(\.relativePath) == ["Empty", "Metadata Only", "Populated"])
    #expect(nodes.allSatisfy { $0.children == nil })
    #expect(nodes.first { $0.name == "Empty" }?.hasChildren == false)
    #expect(nodes.first { $0.name == "Metadata Only" }?.hasChildren == false)
    #expect(nodes.first { $0.name == "Populated" }?.hasChildren == true)
    #expect(!nodes.contains { $0.relativePath.contains("Grandchild") })

    let populatedNodes = try await WorkingCopyFileService().directoryContents(
        at: root.path,
        relativeDirectory: "Populated",
        svnEntries: []
    )
    #expect(populatedNodes.map(\.relativePath) == ["Populated/Grandchild"])
    #expect(populatedNodes.allSatisfy { $0.children == nil })
}

@Test func readsFileMetadataAndLeavesDirectorySizeNil() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-metadata-\(UUID().uuidString)", isDirectory: true)
    let folder = root.appendingPathComponent("Folder", isDirectory: true)
    let file = root.appendingPathComponent("sample.txt")
    let contents = Data("정확한 바이트 크기".utf8)
    let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try contents.write(to: file)
    try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: file.path)
    defer { try? FileManager.default.removeItem(at: root) }

    let expectedValues = try file.resourceValues(
        forKeys: [.contentModificationDateKey, .fileSizeKey, .localizedTypeDescriptionKey]
    )
    let nodes = try await WorkingCopyFileService().directoryContents(
        at: root.path,
        relativeDirectory: "",
        svnEntries: []
    )
    let fileNode = try #require(nodes.first { $0.name == "sample.txt" })
    let folderNode = try #require(nodes.first { $0.name == "Folder" })

    #expect(fileNode.modificationDate == expectedValues.contentModificationDate)
    #expect(fileNode.fileSize == contents.count)
    #expect(fileNode.fileSize == expectedValues.fileSize)
    #expect(fileNode.typeDescription == expectedValues.localizedTypeDescription)
    #expect(fileNode.typeDescription != nil)
    #expect(folderNode.modificationDate != nil)
    #expect(folderNode.typeDescription != nil)
    #expect(folderNode.fileSize == nil)
}

@Test func directListingExcludesSVNAndSortsDirectoriesBeforeFiles() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-direct-sort-\(UUID().uuidString)", isDirectory: true)
    for directory in ["Folder 10", "Folder 2", ".svn"] {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(directory, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    try Data().write(to: root.appendingPathComponent("file 10.txt"))
    try Data().write(to: root.appendingPathComponent("file 2.txt"))
    defer { try? FileManager.default.removeItem(at: root) }

    let nodes = try await WorkingCopyFileService().directoryContents(
        at: root.path,
        relativeDirectory: "",
        svnEntries: []
    )

    #expect(nodes.map(\.name) == ["Folder 2", "Folder 10", "file 2.txt", "file 10.txt"])
    #expect(!nodes.contains { $0.name == ".svn" })
}

@Test func directListingDoesNotFollowSymbolicLinks() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-direct-link-\(UUID().uuidString)", isDirectory: true)
    let target = root.appendingPathComponent("Target", isDirectory: true)
    let package = root.appendingPathComponent("Example.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: target.appendingPathComponent("inside.txt"))
    try Data("resource".utf8).write(to: package.appendingPathComponent("resource.txt"))
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("Target Link"),
        withDestinationURL: target
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let service = WorkingCopyFileService()
    let nodes = try await service.directoryContents(
        at: root.path,
        relativeDirectory: "",
        svnEntries: []
    )
    let link = try #require(nodes.first { $0.name == "Target Link" })
    let packageNode = try #require(nodes.first { $0.name == "Example.bundle" })

    #expect(link.isSymbolicLink)
    #expect(!link.isDirectory)
    #expect(!link.isRegularFile)
    #expect(!link.hasChildren)
    #expect(link.children == nil)
    #expect(!packageNode.isDirectory)
    #expect(!packageNode.hasChildren)
    #expect(packageNode.children == nil)
    #expect(try await service.directoryContents(
        at: root.path,
        relativeDirectory: "Target Link",
        svnEntries: []
    ).isEmpty)
    #expect(try await service.directoryContents(
        at: root.path,
        relativeDirectory: "Example.bundle",
        svnEntries: []
    ).isEmpty)
}

@Test func directListingSurvivesUnreadableItems() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("working-copy-unreadable-\(UUID().uuidString)", isDirectory: true)
    let readable = root.appendingPathComponent("readable.txt")
    let unreadable = root.appendingPathComponent("Unreadable", isDirectory: true)
    try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
    try Data("visible".utf8).write(to: readable)
    try Data("hidden".utf8).write(to: unreadable.appendingPathComponent("hidden.txt"))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        try? FileManager.default.removeItem(at: root)
    }

    let nodes = try await WorkingCopyFileService().directoryContents(
        at: root.path,
        relativeDirectory: "",
        svnEntries: []
    )

    #expect(nodes.map(\.name) == ["Unreadable", "readable.txt"])
    #expect(nodes.first { $0.name == "Unreadable" }?.children == nil)
}
