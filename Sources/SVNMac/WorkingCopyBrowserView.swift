import SwiftUI
import SVNCore

struct WorkingCopyBrowserView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Binding var searchText: String
    @State private var searchTreeState = WorkingCopyBrowserTreeState()
    @State private var isSearching = false
    @State private var sortOrder = [WorkingCopyFileSortComparator(column: .name)]

    var body: some View {
        @Bindable var store = store
        Table(
            of: WorkingCopyFileNode.self,
            selection: $store.selectedBrowserPath,
            sortOrder: $sortOrder
        ) {
            TableColumn(
                appLanguage.localized(.ui.browser.name),
                sortUsing: WorkingCopyFileSortComparator(column: .name)
            ) { node in
                fileNameCell(node)
            }
            .width(
                min: AppLayout.fileBrowserNameColumnMinimumWidth,
                ideal: AppLayout.fileBrowserNameColumnIdealWidth
            )
            TableColumn(
                appLanguage.localized(.ui.browser.dateModified),
                sortUsing: WorkingCopyFileSortComparator(column: .modificationDate)
            ) { node in
                Text(modificationDateText(for: node))
                    .lineLimit(1)
            }
            TableColumn(
                appLanguage.localized(.ui.browser.size),
                sortUsing: WorkingCopyFileSortComparator(column: .size)
            ) { node in
                Text(WorkingCopyFileMetadataFormatting.sizeText(for: node))
                    .lineLimit(1)
            }
            TableColumn(
                appLanguage.localized(.ui.browser.kind),
                sortUsing: WorkingCopyFileSortComparator(column: .kind)
            ) { node in
                Text(node.typeDescription ?? "")
                    .lineLimit(1)
            }
        } rows: {
            WorkingCopyBrowserTableRows(
                nodes: displayedState.rootNodes,
                state: displayedState,
                comparator: currentSortComparator,
                onExpansionChanged: setDirectory(_:expanded:)
            )
        }
        .overlay {
            if showsInitialProgress {
                ProgressView(appLanguage.localized(.ui.browser.loadingFiles))
            } else if displayedState.rootNodes.isEmpty {
                ContentUnavailableView(
                    normalizedSearchText.isEmpty
                        ? appLanguage.localized(.ui.browser.noFiles)
                        : appLanguage.localized(.ui.browser.noSearchResults),
                    systemImage: normalizedSearchText.isEmpty ? "folder" : "magnifyingglass"
                )
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(for: ids)
        } primaryAction: { ids in
            activateRows(ids)
        }
        // 선택이 없을 때도 위아래 키로 첫 행부터 고를 수 있어야 하므로 직접 처리합니다.
        .onKeyPress(.upArrow) {
            handleKey(.up)
        }
        .onKeyPress(.downArrow) {
            handleKey(.down)
        }
        .onKeyPress(.leftArrow) {
            handleKey(.left)
        }
        .onKeyPress(.rightArrow) {
            handleKey(.right)
        }
        .onKeyPress(.return) {
            handleKey(.activate)
        }
        .task(id: searchRequest) {
            await updateSearchResults()
        }
        .task(id: needsLockPathsToLoad) {
            await store.loadNeedsLockState(for: needsLockPathsToLoad)
        }
        .onChange(of: store.errorMessage) { _, message in
            guard let message, SVNClient.isRepositoryConnectionError(message) else { return }
            Task { await store.captureRepositoryConnectionError(message) }
        }
    }

    private func fileNameCell(_ node: WorkingCopyFileNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: node))
                .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
            Text(node.name).lineLimit(1)
            if let status = visibleStatus(for: node) {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if displayedState.loadingPaths.contains(node.relativePath) {
                ProgressView()
                    .controlSize(.small)
            }
            if let lock = lockInfo(for: node) {
                Label(lock.owner, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(lock.owner == store.selectedProject?.username ? Color.accentColor : Color.orange)
                    .help(lockDescription(lock))
            }
            if store.recoveryState.needsLockPaths.contains(node.relativePath) {
                Image(systemName: "lock.square")
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized(.ui.lock.requiredBeforeEditing))
            }
            if node.isSymbolicLink {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized(.ui.browser.symbolicLink))
            }
        }
        // 셀에 탭 제스처를 붙이면 이름 열을 클릭할 때 Table의 행 선택이 가려집니다.
        // 선택과 더블클릭은 Table의 선택 처리와 primaryAction에 맡깁니다.
        .accessibilityAction(named: appLanguage.localized(.ui.common.openFile)) {
            open(node)
        }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<String>) -> some View {
        if let id = ids.first, ids.count == 1, let node = displayedState.node(at: id) {
            if !node.isDirectory {
                Button(appLanguage.localized(.ui.common.openFile)) {
                    open(node)
                }
                if let lock = lockInfo(for: node),
                   lock.owner == store.selectedProject?.username {
                    Button(appLanguage.localized(.ui.lock.releaseFromBrowserAction)) {
                        Task { await store.unlock(lock) }
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                }
            }
            Button(appLanguage.localized(.ui.common.revealFinder)) {
                store.revealInFinder(node.relativePath)
            }
            Button(appLanguage.localized(.ui.common.copyFullPath)) {
                store.copyPath(node.relativePath)
            }
            if node.isRegularFile, node.isVersioned {
                Divider()
                if lockInfo(for: node)?.owner != store.selectedProject?.username {
                    Button(
                        lockInfo(for: node) == nil
                            ? appLanguage.localized(.ui.lock.file)
                            : appLanguage.localized(.ui.lock.reviewForceLock)
                    ) {
                        Task { await store.prepareExplicitLock(paths: [node.repositoryRelativePath]) }
                    }
                }
                Button(appLanguage.localized(.ui.history.fileCommitHistory)) {
                    Task { await store.loadFileHistory(for: node.repositoryRelativePath) }
                }
                Button(appLanguage.localized(.ui.history.renameHistory)) {
                    store.requestVersionedFileAction(.move, path: node.relativePath)
                }
                Button(appLanguage.localized(.ui.history.copyHistory)) {
                    store.requestVersionedFileAction(.copy, path: node.relativePath)
                }
                if store.recoveryState.needsLockPaths.contains(node.relativePath) {
                    Button(appLanguage.localized(.ui.lock.removeRequiredLock)) {
                        Task { _ = await store.setNeedsLock(false, paths: [node.relativePath]) }
                    }
                } else {
                    Button(appLanguage.localized(.ui.lock.requireLockBeforeEditing)) {
                        Task { _ = await store.setNeedsLock(true, paths: [node.relativePath]) }
                    }
                }
            }
        }
    }

    private var needsLockPathsToLoad: [String] {
        displayedState.visibleRows()
            .filter { !$0.isDirectory && $0.isVersioned && $0.isRegularFile }
            .map(\.relativePath)
    }

    /// 더블클릭은 파일이면 열고 폴더면 펼침 상태를 토글합니다.
    private func activateRows(_ ids: Set<String>) {
        guard let id = ids.first, ids.count == 1, let node = displayedState.node(at: id) else { return }
        guard node.isDirectory else {
            open(node)
            return
        }
        setDirectory(node.relativePath, expanded: !displayedState.expandedPaths.contains(node.relativePath))
    }

    private var displayedState: WorkingCopyBrowserTreeState {
        normalizedSearchText.isEmpty ? store.workingCopyBrowserTreeState : searchTreeState
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSortComparator: WorkingCopyFileSortComparator {
        sortOrder.first ?? WorkingCopyFileSortComparator(column: .name)
    }

    private var searchRequest: WorkingCopyBrowserSearchRequest {
        WorkingCopyBrowserSearchRequest(
            projectID: store.selectedProjectID,
            generation: store.workingCopyBrowserTreeState.generation,
            query: normalizedSearchText
        )
    }

    private var showsInitialProgress: Bool {
        if !normalizedSearchText.isEmpty { return isSearching }
        guard let projectID = store.selectedProjectID else { return false }
        return store.workingCopyBrowserTreeState.rootNodes.isEmpty
            && store.activeOperations.contains { $0.kind == .browseFiles(projectID) }
    }

    private func updateSearchResults() async {
        guard !normalizedSearchText.isEmpty else {
            isSearching = false
            searchTreeState = WorkingCopyBrowserTreeState()
            return
        }

        isSearching = true
        guard let tree = await store.searchWorkingCopyFiles(query: normalizedSearchText),
              !Task.isCancelled else { return }
        searchTreeState = WorkingCopyBrowserTreeState(recursiveTree: tree, expanded: true)
        isSearching = false
    }

    private func setDirectory(_ relativePath: String, expanded: Bool) {
        if normalizedSearchText.isEmpty {
            if let directoryToLoad = store.setWorkingCopyDirectory(relativePath, expanded: expanded) {
                Task { await store.loadWorkingCopyDirectory(directoryToLoad) }
            }
        } else {
            var state = searchTreeState
            _ = state.setExpanded(expanded, for: relativePath)
            searchTreeState = state
        }
    }

    private func handleKey(_ command: WorkingCopyBrowserKeyCommand) -> KeyPress.Result {
        // 선택이 없을 때는 위아래 키만 받아 첫 행을 고르고, 나머지 키는 흘려보냅니다.
        guard store.selectedBrowserPath != nil || command == .up || command == .down else {
            return .ignored
        }

        let result: WorkingCopyBrowserNavigationResult
        if normalizedSearchText.isEmpty {
            result = store.applyWorkingCopyBrowserKey(command, sortedBy: currentSortComparator)
        } else {
            var state = searchTreeState
            result = state.handle(
                command,
                selectedPath: store.selectedBrowserPath,
                sortedBy: currentSortComparator
            )
            searchTreeState = state
            store.selectedBrowserPath = result.selectedPath
        }

        if let directoryToLoad = result.directoryToLoad, normalizedSearchText.isEmpty {
            Task { await store.loadWorkingCopyDirectory(directoryToLoad) }
        }
        if let fileToOpen = result.fileToOpen {
            open(fileToOpen)
        }
        return .handled
    }

    private func open(_ node: WorkingCopyFileNode) {
        guard !node.isDirectory else { return }
        Task {
            await store.prepareToOpen(
                path: node.relativePath,
                repositoryPath: node.repositoryRelativePath,
                isVersioned: node.isVersioned,
                isRegularFile: node.isRegularFile
            )
        }
    }

    private func modificationDateText(for node: WorkingCopyFileNode) -> String {
        guard let modificationDate = node.modificationDate else { return "" }
        return WorkingCopyFileDateFormatting.shared.string(
            from: modificationDate,
            language: appLanguage
        )
    }

    private func iconName(for node: WorkingCopyFileNode) -> String {
        if node.isDirectory { return "folder" }
        switch (node.name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "tiff", "heic", "webp": return "photo"
        case "doc", "docx", "pages": return "doc.richtext"
        case "xls", "xlsx", "numbers": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "pdf": return "doc.text"
        default: return "doc"
        }
    }

    private func visibleStatus(for node: WorkingCopyFileNode) -> String? {
        guard let status = node.svnEntry?.status, status != "normal" else { return nil }
        switch status {
        case "modified": return appLanguage.localized(.ui.status.modified)
        case "added": return appLanguage.localized(.ui.status.added)
        case "unversioned": return appLanguage.localized(.ui.status.unversioned)
        case "ignored": return appLanguage.localized(.ui.status.ignored)
        case "conflicted": return appLanguage.localized(.ui.conflict.conflict)
        default: return status
        }
    }

    private func lockInfo(for node: WorkingCopyFileNode) -> SVNLockInfo? {
        store.repositoryLocks.first { node.matchesRepositoryPath($0.path) }
    }

    private func lockDescription(_ lock: SVNLockInfo) -> String {
        if lock.owner == store.selectedProject?.username {
            return appLanguage.localized(.ui.lock.lockedByCurrentUser)
        }
        return appLanguage.localized(.ui.lock.lockedByOwner, lock.owner)
    }
}

private struct WorkingCopyBrowserTableRows: TableRowContent {
    let nodes: [WorkingCopyFileNode]
    let state: WorkingCopyBrowserTreeState
    let comparator: WorkingCopyFileSortComparator
    let onExpansionChanged: (String, Bool) -> Void

    @TableRowBuilder<WorkingCopyFileNode>
    var tableRowBody: some TableRowContent<WorkingCopyFileNode> {
        ForEach(nodes.sorted(using: comparator)) { node in
            if node.isDirectory, node.hasChildren {
                DisclosureTableRow(
                    node,
                    isExpanded: Binding(
                        get: { state.expandedPaths.contains(node.relativePath) },
                        set: { onExpansionChanged(node.relativePath, $0) }
                    )
                ) {
                    WorkingCopyBrowserTableRows(
                        nodes: state.children(of: node),
                        state: state,
                        comparator: comparator,
                        onExpansionChanged: onExpansionChanged
                    )
                }
            } else {
                TableRow(node)
            }
        }
    }
}

private struct WorkingCopyBrowserSearchRequest: Hashable {
    let projectID: SVNProject.ID?
    let generation: UUID
    let query: String
}
