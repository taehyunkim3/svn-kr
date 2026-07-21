import Foundation
import SVNCore

struct WorkingCopyFileNode: Identifiable, Hashable, Sendable {
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isRegularFile: Bool
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
        svnEntry: SVNWorkingCopyEntry?,
        children: [WorkingCopyFileNode]?
    ) {
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.isRegularFile = isRegularFile ?? (!isDirectory && !isSymbolicLink)
        self.svnEntry = svnEntry
        self.children = children
    }
}

protocol WorkingCopyFileListing: Sendable {
    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) async throws -> [WorkingCopyFileNode]
}

/// 사용자가 허용한 작업 폴더 안의 실제 파일을 Finder와 같은 계층으로 읽습니다.
actor WorkingCopyFileService: WorkingCopyFileListing {
    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) throws -> [WorkingCopyFileNode] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let entriesByPath = svnEntries.reduce(into: [SVNPathIdentity: SVNWorkingCopyEntry]()) { result, entry in
            result[SVNPathIdentity(rawPath: entry.path)] = entry
        }
        return try children(of: rootURL, relativeDirectory: "", entriesByPath: entriesByPath)
    }

    private func children(
        of directoryURL: URL,
        relativeDirectory: String,
        entriesByPath: [SVNPathIdentity: SVNWorkingCopyEntry]
    ) throws -> [WorkingCopyFileNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        return try urls.compactMap { url in
            guard url.lastPathComponent != ".svn" else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            let relativePath = relativeDirectory.isEmpty
                ? url.lastPathComponent
                : relativeDirectory + "/" + url.lastPathComponent
            let isSymbolicLink = values.isSymbolicLink == true
            let isDirectory = values.isDirectory == true
                && !isSymbolicLink
                && values.isPackage != true
            let nestedChildren = isDirectory
                ? try children(of: url, relativeDirectory: relativePath, entriesByPath: entriesByPath)
                : nil
            return WorkingCopyFileNode(
                name: url.lastPathComponent,
                relativePath: relativePath,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink,
                isRegularFile: values.isRegularFile == true && !isSymbolicLink && values.isPackage != true,
                svnEntry: entriesByPath[SVNPathIdentity(rawPath: relativePath)],
                children: nestedChildren
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
