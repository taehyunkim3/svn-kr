import Foundation
import SVNCore

struct WorkingCopyFileNode: Identifiable, Hashable, Sendable {
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isRegularFile: Bool
    let modificationDate: Date?
    let fileSize: Int?
    let typeDescription: String?
    let hasChildren: Bool
    let svnEntry: SVNWorkingCopyEntry?
    let children: [WorkingCopyFileNode]?

    var id: String { relativePath }
    var isVersioned: Bool { svnEntry?.isVersioned == true }
    var repositoryRelativePath: String { svnEntry?.repositoryRelativePath ?? relativePath }

    func matchesRepositoryPath(_ path: String) -> Bool {
        Data(repositoryRelativePath.utf8) == Data(path.utf8)
    }

    init(
        name: String,
        relativePath: String,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        isRegularFile: Bool? = nil,
        modificationDate: Date? = nil,
        fileSize: Int? = nil,
        typeDescription: String? = nil,
        hasChildren: Bool? = nil,
        svnEntry: SVNWorkingCopyEntry?,
        children: [WorkingCopyFileNode]?
    ) {
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.isRegularFile = isRegularFile ?? (!isDirectory && !isSymbolicLink)
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.typeDescription = typeDescription
        self.hasChildren = hasChildren ?? (children?.isEmpty == false)
        self.svnEntry = svnEntry
        self.children = children
    }

    var withoutLoadedChildren: WorkingCopyFileNode {
        WorkingCopyFileNode(
            name: name,
            relativePath: relativePath,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            isRegularFile: isRegularFile,
            modificationDate: modificationDate,
            fileSize: fileSize,
            typeDescription: typeDescription,
            hasChildren: hasChildren,
            svnEntry: svnEntry,
            children: nil
        )
    }
}

protocol WorkingCopyFileListing: Sendable {
    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) async throws -> [WorkingCopyFileNode]
    func directoryContents(
        at rootPath: String,
        relativeDirectory: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) async throws -> [WorkingCopyFileNode]
}

extension WorkingCopyFileListing {
    /// 테스트 대역 등 기존 구현의 소스 호환성을 위한 기본 구현입니다.
    /// 실제 파일 서비스는 직계 자식만 읽는 구현을 사용합니다.
    func directoryContents(
        at rootPath: String,
        relativeDirectory: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) async throws -> [WorkingCopyFileNode] {
        let tree = try await tree(at: rootPath, svnEntries: svnEntries)
        let contents = relativeDirectory.isEmpty
            ? tree
            : tree.node(at: relativeDirectory)?.children ?? []
        return contents.map(\.withoutLoadedChildren)
    }
}

/// 사용자가 허용한 작업 폴더 안의 실제 파일을 Finder와 같은 계층으로 읽습니다.
actor WorkingCopyFileService: WorkingCopyFileListing {
    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) throws -> [WorkingCopyFileNode] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        return try loadChildren(
            of: rootURL,
            relativeDirectory: "",
            entriesByPath: entriesByPath(svnEntries),
            recursively: true
        )
    }

    func directoryContents(
        at rootPath: String,
        relativeDirectory: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) throws -> [WorkingCopyFileNode] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let directoryURL = directoryURL(
            rootURL: rootURL,
            relativeDirectory: relativeDirectory
        ) else { return [] }
        return try loadChildren(
            of: directoryURL,
            relativeDirectory: relativeDirectory,
            entriesByPath: entriesByPath(svnEntries),
            recursively: false
        )
    }

    private func directoryURL(rootURL: URL, relativeDirectory: String) -> URL? {
        guard !relativeDirectory.isEmpty else { return rootURL }

        var directoryURL = rootURL
        for component in relativeDirectory.split(separator: "/", omittingEmptySubsequences: false) {
            guard component != ".", component != "..", !component.isEmpty else { return nil }
            directoryURL.appendPathComponent(String(component), isDirectory: true)
            guard let values = try? directoryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
            ),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            values.isPackage != true else { return nil }
        }
        return directoryURL
    }

    private func entriesByPath(
        _ svnEntries: [SVNWorkingCopyEntry]
    ) -> [SVNPathIdentity: SVNWorkingCopyEntry] {
        svnEntries.reduce(into: [SVNPathIdentity: SVNWorkingCopyEntry]()) { result, entry in
            result[SVNPathIdentity(rawPath: entry.path)] = entry
        }
    }

    private func loadChildren(
        of directoryURL: URL,
        relativeDirectory: String,
        entriesByPath: [SVNPathIdentity: SVNWorkingCopyEntry],
        recursively: Bool
    ) throws -> [WorkingCopyFileNode] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedTypeDescriptionKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        return urls.compactMap { url in
            guard url.lastPathComponent != ".svn" else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            let relativePath = relativeDirectory.isEmpty
                ? url.lastPathComponent
                : relativeDirectory + "/" + url.lastPathComponent
            let isSymbolicLink = values?.isSymbolicLink == true
            let isDirectory = values?.isDirectory == true
                && !isSymbolicLink
                && values?.isPackage != true
            let nestedChildren = isDirectory && recursively
                ? try? loadChildren(
                    of: url,
                    relativeDirectory: relativePath,
                    entriesByPath: entriesByPath,
                    recursively: true
                )
                : nil
            let hasChildren = isDirectory
                ? nestedChildren?.isEmpty == false || (nestedChildren == nil && containsVisibleChild(at: url))
                : false
            return WorkingCopyFileNode(
                name: url.lastPathComponent,
                relativePath: relativePath,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink,
                isRegularFile: values?.isRegularFile == true && !isSymbolicLink && values?.isPackage != true,
                modificationDate: values?.contentModificationDate,
                fileSize: isDirectory ? nil : values?.fileSize,
                typeDescription: values?.localizedTypeDescription,
                hasChildren: hasChildren,
                svnEntry: entriesByPath[SVNPathIdentity(rawPath: relativePath)],
                children: nestedChildren
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func containsVisibleChild(at directoryURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [],
            options: [.skipsSubdirectoryDescendants]
        ) else { return false }

        while let childURL = enumerator.nextObject() as? URL {
            if childURL.lastPathComponent != ".svn" { return true }
        }
        return false
    }
}

extension Array where Element == WorkingCopyFileNode {
    func node(at relativePath: String) -> WorkingCopyFileNode? {
        for node in self {
            if node.relativePath == relativePath { return node }
            if let match = node.children?.node(at: relativePath) { return match }
        }
        return nil
    }
}
