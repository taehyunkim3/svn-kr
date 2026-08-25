import Foundation

struct WorkingCopySplitBrowserState: Equatable {
    enum FocusedPanel: Hashable {
        case folders
        case contents
    }

    struct FolderRow: Identifiable, Equatable {
        let name: String
        let relativePath: String
        let depth: Int
        let hasChildren: Bool

        var id: String { relativePath }
    }

    private(set) var directoryContentsByPath: [String: [WorkingCopyFileNode]] = [:]
    var expandedDirectoryPaths: Set<String> = [""]
    var selectedFolderPath = ""
    var currentDirectoryPath = ""
    var selectedContentPath: String?
    var focusedPanel: FocusedPanel = .folders

    var currentDirectoryContents: [WorkingCopyFileNode] {
        directoryContentsByPath[currentDirectoryPath] ?? []
    }

    func isDirectoryCached(_ relativePath: String) -> Bool {
        directoryContentsByPath[relativePath] != nil
    }

    mutating func cache(_ contents: [WorkingCopyFileNode], for relativeDirectory: String) {
        directoryContentsByPath[relativeDirectory] = contents
    }

    mutating func clearCacheForRefresh() {
        directoryContentsByPath.removeAll()
    }

    mutating func replaceCacheForRefresh(
        _ refreshedContentsByPath: [String: [WorkingCopyFileNode]],
        preservingCachedPaths: Set<String> = []
    ) {
        let preservedContents = directoryContentsByPath.filter {
            preservingCachedPaths.contains($0.key) && refreshedContentsByPath[$0.key] == nil
        }
        directoryContentsByPath = refreshedContentsByPath.merging(preservedContents) { refreshed, _ in
            refreshed
        }
    }

    func folderChildren(of relativeDirectory: String) -> [WorkingCopyFileNode] {
        (directoryContentsByPath[relativeDirectory] ?? []).filter(\.isDirectory)
    }

    func visibleFolderRows(rootName: String) -> [FolderRow] {
        var rows = [FolderRow(
            name: rootName,
            relativePath: "",
            depth: 0,
            hasChildren: directoryContentsByPath[""]?.contains(where: \.isDirectory) ?? true
        )]
        guard expandedDirectoryPaths.contains("") else { return rows }
        appendVisibleFolderRows(in: "", depth: 1, to: &rows)
        return rows
    }

    mutating func selectFolder(_ relativePath: String) {
        let directoryChanged = currentDirectoryPath != relativePath
        selectedFolderPath = relativePath
        currentDirectoryPath = relativePath
        if directoryChanged {
            selectedContentPath = nil
        }
        expandAncestors(of: relativePath)
    }

    mutating func selectContent(_ relativePath: String?) {
        selectedContentPath = relativePath
    }

    mutating func moveContentSelection(
        by offset: Int,
        in displayedContents: [WorkingCopyFileNode]
    ) {
        guard !displayedContents.isEmpty else { return }
        let currentIndex = displayedContents.firstIndex { $0.relativePath == selectedContentPath }
            ?? (offset < 0 ? displayedContents.endIndex : displayedContents.startIndex - 1)
        let destination = min(
            max(currentIndex + offset, displayedContents.startIndex),
            displayedContents.index(before: displayedContents.endIndex)
        )
        selectedContentPath = displayedContents[destination].relativePath
    }

    mutating func moveFolderSelection(
        by offset: Int,
        rootName: String
    ) {
        let rows = visibleFolderRows(rootName: rootName)
        guard !rows.isEmpty else { return }
        let currentIndex = rows.firstIndex { $0.relativePath == selectedFolderPath } ?? 0
        let destination = min(max(currentIndex + offset, rows.startIndex), rows.index(before: rows.endIndex))
        let destinationPath = rows[destination].relativePath
        guard destinationPath != selectedFolderPath else { return }
        selectFolder(destinationPath)
    }

    /// 펼칠 폴더를 아직 읽지 않았다면 해당 경로를 반환합니다.
    @discardableResult
    mutating func moveFolderRight() -> String? {
        let path = selectedFolderPath
        guard folderCanHaveChildren(path) else { return nil }

        if !expandedDirectoryPaths.contains(path) {
            expandedDirectoryPaths.insert(path)
            return isDirectoryCached(path) ? nil : path
        }

        guard let firstChild = folderChildren(of: path).first else {
            return isDirectoryCached(path) ? nil : path
        }
        selectFolder(firstChild.relativePath)
        return isDirectoryCached(firstChild.relativePath) ? nil : firstChild.relativePath
    }

    mutating func moveFolderLeft() {
        let path = selectedFolderPath
        if expandedDirectoryPaths.contains(path) {
            expandedDirectoryPaths.remove(path)
            return
        }
        guard let parent = Self.parentDirectory(of: path) else { return }
        selectFolder(parent)
    }

    @discardableResult
    mutating func toggleFolderExpansion(_ relativePath: String) -> String? {
        if expandedDirectoryPaths.contains(relativePath) {
            expandedDirectoryPaths.remove(relativePath)
            return nil
        }
        expandedDirectoryPaths.insert(relativePath)
        return isDirectoryCached(relativePath) ? nil : relativePath
    }

    mutating func enterDirectory(_ relativePath: String) {
        selectFolder(relativePath)
        expandedDirectoryPaths.insert(relativePath)
    }

    mutating func moveToParentDirectory() {
        guard let parent = Self.parentDirectory(of: currentDirectoryPath) else { return }
        selectFolder(parent)
    }

    mutating func moveFocus(reverse _: Bool = false) {
        focusedPanel = focusedPanel == .folders ? .contents : .folders
    }

    static func parentDirectory(of relativePath: String) -> String? {
        guard !relativePath.isEmpty else { return nil }
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    private func appendVisibleFolderRows(
        in relativeDirectory: String,
        depth: Int,
        to rows: inout [FolderRow]
    ) {
        for folder in folderChildren(of: relativeDirectory) {
            rows.append(FolderRow(
                name: folder.name,
                relativePath: folder.relativePath,
                depth: depth,
                hasChildren: directoryContentsByPath[folder.relativePath]?
                    .contains(where: \.isDirectory) ?? folder.hasChildren
            ))
            if expandedDirectoryPaths.contains(folder.relativePath) {
                appendVisibleFolderRows(
                    in: folder.relativePath,
                    depth: depth + 1,
                    to: &rows
                )
            }
        }
    }

    private func folderCanHaveChildren(_ relativePath: String) -> Bool {
        if relativePath.isEmpty {
            return directoryContentsByPath[""]?.contains(where: \.isDirectory) ?? true
        }
        if let loadedContents = directoryContentsByPath[relativePath] {
            return loadedContents.contains(where: \.isDirectory)
        }
        let parent = Self.parentDirectory(of: relativePath) ?? ""
        return folderChildren(of: parent)
            .first { $0.relativePath == relativePath }?
            .hasChildren == true
    }

    private mutating func expandAncestors(of relativePath: String) {
        expandedDirectoryPaths.insert("")
        var ancestor = Self.parentDirectory(of: relativePath)
        while let path = ancestor {
            expandedDirectoryPaths.insert(path)
            ancestor = Self.parentDirectory(of: path)
        }
    }
}
