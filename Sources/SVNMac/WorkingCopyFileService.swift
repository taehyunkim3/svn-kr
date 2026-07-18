import Foundation
import SVNCore

struct WorkingCopyFileNode: Identifiable, Hashable, Sendable {
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let svnEntry: SVNWorkingCopyEntry?
    let children: [WorkingCopyFileNode]?

    var id: String { relativePath }
    var isVersioned: Bool { svnEntry?.isVersioned == true }
}

protocol WorkingCopyFileListing: Sendable {
    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) async throws -> [WorkingCopyFileNode]
}

/// 사용자가 허용한 작업 폴더 안의 실제 파일을 Finder와 같은 계층으로 읽습니다.
actor WorkingCopyFileService: WorkingCopyFileListing {
    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) throws -> [WorkingCopyFileNode] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let entriesByPath = Dictionary(uniqueKeysWithValues: svnEntries.map { ($0.path, $0) })
        return try children(of: rootURL, relativeDirectory: "", entriesByPath: entriesByPath)
    }

    private func children(
        of directoryURL: URL,
        relativeDirectory: String,
        entriesByPath: [String: SVNWorkingCopyEntry]
    ) throws -> [WorkingCopyFileNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
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
                svnEntry: entriesByPath[relativePath],
                children: nestedChildren
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
