import Foundation

enum WorkingCopyBrowserKeyCommand: Sendable {
    case up
    case down
    case left
    case right
    case activate
}

struct WorkingCopyBrowserNavigationResult: Equatable, Sendable {
    var selectedPath: String?
    var directoryToLoad: String?
    var fileToOpen: WorkingCopyFileNode?
}

struct WorkingCopyBrowserRefreshPlan: Equatable, Sendable {
    let directoryPaths: [String]
    let selectionAncestorPaths: Set<String>

    func shouldRestoreDirectory(
        _ relativePath: String,
        expandedPaths: Set<String>
    ) -> Bool {
        expandedPaths.contains(relativePath) || selectionAncestorPaths.contains(relativePath)
    }
}

enum WorkingCopyFileSortColumn: Hashable, Sendable {
    case name
    case modificationDate
    case size
    case kind
}

struct WorkingCopyFileSortComparator: SortComparator, Hashable, Sendable {
    let column: WorkingCopyFileSortColumn
    var order: SortOrder = .forward

    func compare(_ lhs: WorkingCopyFileNode, _ rhs: WorkingCopyFileNode) -> ComparisonResult {
        // Finder와 마찬가지로 어떤 열을 정렬하더라도 폴더 그룹은 파일보다 먼저 둡니다.
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory ? .orderedAscending : .orderedDescending
        }

        let result = switch column {
        case .name:
            lhs.name.localizedStandardCompare(rhs.name)
        case .modificationDate:
            compareOptional(lhs.modificationDate, rhs.modificationDate)
        case .size:
            compareOptional(lhs.fileSize, rhs.fileSize)
        case .kind:
            (lhs.typeDescription ?? "").localizedStandardCompare(rhs.typeDescription ?? "")
        }
        guard order == .reverse else { return result }
        return result.reversed
    }

    private func compareOptional<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
            return .orderedSame
        case (_?, nil):
            return .orderedAscending
        case (nil, _?):
            return .orderedDescending
        case (nil, nil):
            return .orderedSame
        }
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

struct WorkingCopyBrowserTreeState: Equatable, Sendable {
    private(set) var rootNodes: [WorkingCopyFileNode] = []
    var expandedPaths: Set<String> = []
    private(set) var childrenByDirectory: [String: [WorkingCopyFileNode]] = [:]
    var loadingPaths: Set<String> = []
    private(set) var generation = UUID()

    init() {}

    init(recursiveTree: [WorkingCopyFileNode], expanded: Bool = false) {
        replace(withRecursiveTree: recursiveTree, expanded: expanded)
    }

    var materializedTree: [WorkingCopyFileNode] {
        materialize(rootNodes)
    }

    mutating func reset(rootNodes: [WorkingCopyFileNode] = []) {
        self.rootNodes = rootNodes.map(\.withoutLoadedChildren)
        expandedPaths.removeAll()
        childrenByDirectory.removeAll()
        loadingPaths.removeAll()
        generation = UUID()
    }

    /// 같은 작업 사본을 새로고침할 때 펼침 상태는 남기고, 다시 읽어야 하는
    /// 디렉터리 캐시와 진행 중 요청만 폐기합니다.
    mutating func prepareForRefresh() {
        rootNodes = rootNodes.map(\.withoutLoadedChildren)
        childrenByDirectory.removeAll()
        loadingPaths.removeAll()
        generation = UUID()
    }

    /// 새 루트를 적용하는 순간 그 사이 시작된 자식 읽기도 무효화합니다.
    /// 사용자가 새로고침 중 바꾼 펼침 상태는 그대로 둡니다.
    mutating func replaceRootNodesForRefresh(_ rootNodes: [WorkingCopyFileNode]) {
        self.rootNodes = rootNodes.map(\.withoutLoadedChildren)
        childrenByDirectory.removeAll()
        loadingPaths.removeAll()
        generation = UUID()
    }

    func refreshPlan(selectedPath: String?) -> WorkingCopyBrowserRefreshPlan {
        let selectionAncestors = selectedPath.map(directoryAncestors) ?? []
        let paths = expandedPaths
            .union(selectionAncestors)
            .sorted {
                let lhsDepth = pathDepth($0)
                let rhsDepth = pathDepth($1)
                return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
            }
        return WorkingCopyBrowserRefreshPlan(
            directoryPaths: paths,
            selectionAncestorPaths: selectionAncestors
        )
    }

    mutating func finishRefresh(selectedPath: String?) -> String? {
        expandedPaths = expandedPaths.filter { path in
            guard let node = node(at: path) else { return false }
            return node.isDirectory && node.hasChildren
        }
        guard let selectedPath, node(at: selectedPath) != nil else { return nil }
        return selectedPath
    }

    mutating func replace(withRecursiveTree tree: [WorkingCopyFileNode], expanded: Bool = false) {
        reset(rootNodes: tree)
        cacheRecursively(tree, expandDirectories: expanded)
    }

    mutating func cache(_ children: [WorkingCopyFileNode], for directoryPath: String) {
        childrenByDirectory[directoryPath] = children.map(\.withoutLoadedChildren)
        loadingPaths.remove(directoryPath)
        cacheRecursively(children, expandDirectories: false)
    }

    mutating func setLoading(_ isLoading: Bool, for directoryPath: String) {
        if isLoading {
            loadingPaths.insert(directoryPath)
        } else {
            loadingPaths.remove(directoryPath)
        }
    }

    func hasCachedChildren(for directoryPath: String) -> Bool {
        childrenByDirectory[directoryPath] != nil
    }

    func children(of node: WorkingCopyFileNode) -> [WorkingCopyFileNode] {
        childrenByDirectory[node.relativePath] ?? []
    }

    func node(at relativePath: String) -> WorkingCopyFileNode? {
        if let node = rootNodes.first(where: { $0.relativePath == relativePath }) {
            return node
        }
        for children in childrenByDirectory.values {
            if let node = children.first(where: { $0.relativePath == relativePath }) {
                return node
            }
        }
        return nil
    }

    func visibleRows(
        sortedBy comparator: WorkingCopyFileSortComparator = .init(column: .name)
    ) -> [WorkingCopyFileNode] {
        var result: [WorkingCopyFileNode] = []
        appendVisible(rootNodes, to: &result, sortedBy: comparator)
        return result
    }

    mutating func setExpanded(_ isExpanded: Bool, for directoryPath: String) -> String? {
        guard let node = node(at: directoryPath), node.isDirectory, node.hasChildren else {
            return nil
        }
        if isExpanded {
            expandedPaths.insert(directoryPath)
            return hasCachedChildren(for: directoryPath) ? nil : directoryPath
        }
        expandedPaths.remove(directoryPath)
        return nil
    }

    mutating func handle(
        _ command: WorkingCopyBrowserKeyCommand,
        selectedPath: String?,
        sortedBy comparator: WorkingCopyFileSortComparator = .init(column: .name)
    ) -> WorkingCopyBrowserNavigationResult {
        let visibleRows = visibleRows(sortedBy: comparator)
        guard let selectedPath,
              let selectedIndex = visibleRows.firstIndex(where: { $0.relativePath == selectedPath }) else {
            let initialSelection = command == .down || command == .up
                ? visibleRows.first?.relativePath
                : nil
            return WorkingCopyBrowserNavigationResult(selectedPath: initialSelection)
        }
        let selectedNode = visibleRows[selectedIndex]

        switch command {
        case .up:
            let index = max(visibleRows.startIndex, selectedIndex - 1)
            return WorkingCopyBrowserNavigationResult(selectedPath: visibleRows[index].relativePath)
        case .down:
            let index = min(visibleRows.index(before: visibleRows.endIndex), selectedIndex + 1)
            return WorkingCopyBrowserNavigationResult(selectedPath: visibleRows[index].relativePath)
        case .right:
            guard selectedNode.isDirectory, selectedNode.hasChildren else {
                return WorkingCopyBrowserNavigationResult(selectedPath: selectedPath)
            }
            if expandedPaths.contains(selectedPath) {
                let firstChild = children(of: selectedNode).sorted(using: comparator).first
                return WorkingCopyBrowserNavigationResult(
                    selectedPath: firstChild?.relativePath ?? selectedPath,
                    directoryToLoad: firstChild == nil && !hasCachedChildren(for: selectedPath)
                        ? selectedPath
                        : nil
                )
            }
            let directoryToLoad = setExpanded(true, for: selectedPath)
            return WorkingCopyBrowserNavigationResult(
                selectedPath: selectedPath,
                directoryToLoad: directoryToLoad
            )
        case .left:
            if selectedNode.isDirectory, expandedPaths.contains(selectedPath) {
                expandedPaths.remove(selectedPath)
                return WorkingCopyBrowserNavigationResult(selectedPath: selectedPath)
            }
            return WorkingCopyBrowserNavigationResult(
                selectedPath: parentPath(of: selectedPath).flatMap { node(at: $0)?.relativePath }
                    ?? selectedPath
            )
        case .activate:
            if selectedNode.isDirectory {
                let isExpanded = expandedPaths.contains(selectedPath)
                let directoryToLoad = setExpanded(!isExpanded, for: selectedPath)
                return WorkingCopyBrowserNavigationResult(
                    selectedPath: selectedPath,
                    directoryToLoad: directoryToLoad
                )
            }
            return WorkingCopyBrowserNavigationResult(
                selectedPath: selectedPath,
                fileToOpen: selectedNode
            )
        }
    }

    private mutating func cacheRecursively(
        _ nodes: [WorkingCopyFileNode],
        expandDirectories: Bool
    ) {
        for node in nodes where node.isDirectory {
            guard let children = node.children else { continue }
            childrenByDirectory[node.relativePath] = children.map(\.withoutLoadedChildren)
            if expandDirectories, node.hasChildren {
                expandedPaths.insert(node.relativePath)
            }
            cacheRecursively(children, expandDirectories: expandDirectories)
        }
    }

    private func appendVisible(
        _ nodes: [WorkingCopyFileNode],
        to result: inout [WorkingCopyFileNode],
        sortedBy comparator: WorkingCopyFileSortComparator
    ) {
        for node in nodes.sorted(using: comparator) {
            result.append(node)
            guard node.isDirectory, expandedPaths.contains(node.relativePath) else { continue }
            appendVisible(children(of: node), to: &result, sortedBy: comparator)
        }
    }

    private func materialize(_ nodes: [WorkingCopyFileNode]) -> [WorkingCopyFileNode] {
        nodes.map { node in
            WorkingCopyFileNode(
                name: node.name,
                relativePath: node.relativePath,
                isDirectory: node.isDirectory,
                isSymbolicLink: node.isSymbolicLink,
                isRegularFile: node.isRegularFile,
                modificationDate: node.modificationDate,
                fileSize: node.fileSize,
                typeDescription: node.typeDescription,
                hasChildren: node.hasChildren,
                svnEntry: node.svnEntry,
                children: node.isDirectory
                    ? childrenByDirectory[node.relativePath].map(materialize)
                    : nil
            )
        }
    }

    private func parentPath(of relativePath: String) -> String? {
        guard let separator = relativePath.lastIndex(of: "/") else { return nil }
        return String(relativePath[..<separator])
    }

    private func directoryAncestors(of relativePath: String) -> Set<String> {
        var result: Set<String> = []
        var ancestor = parentPath(of: relativePath)
        while let path = ancestor {
            result.insert(path)
            ancestor = parentPath(of: path)
        }
        return result
    }

    private func pathDepth(_ relativePath: String) -> Int {
        relativePath.split(separator: "/").count
    }
}

enum WorkingCopyFileMetadataFormatting {
    static func sizeText(for node: WorkingCopyFileNode) -> String {
        guard !node.isDirectory, let fileSize = node.fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

final class WorkingCopyFileDateFormatting: @unchecked Sendable {
    static let shared = WorkingCopyFileDateFormatting()

    private let lock = NSLock()
    private var formatters: [AppLanguage: DateFormatter] = [:]

    func string(from date: Date, language: AppLanguage) -> String {
        lock.withLock {
            let formatter = formatters[language] ?? {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: language == .english ? "en_US" : "ko_KR")
                formatter.timeZone = .autoupdatingCurrent
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                formatters[language] = formatter
                return formatter
            }()
            // 커밋 시각 설정과 무관한 파일시스템 수정 시각이므로 항상 Mac 로컬 시간대를 쓴다.
            formatter.timeZone = .autoupdatingCurrent
            return formatter.string(from: date)
        }
    }
}

struct WorkingCopyFileTreeFilterInput: Hashable, Sendable {
    let tree: [WorkingCopyFileNode]
    let query: String

    var filteredTree: [WorkingCopyFileNode] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return tree }
        return tree.compactMap { $0.filtering(query: normalizedQuery) }
    }
}

private extension WorkingCopyFileNode {
    func filtering(query: String) -> WorkingCopyFileNode? {
        let filteredChildren = children?.compactMap { $0.filtering(query: query) }
        let matches = name.localizedCaseInsensitiveContains(query)
            || relativePath.localizedCaseInsensitiveContains(query)
        guard matches || filteredChildren?.isEmpty == false else { return nil }
        return WorkingCopyFileNode(
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
            children: filteredChildren
        )
    }
}
