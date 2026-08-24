import SwiftUI
import SVNCore

struct WorkingCopySplitBrowserView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @State private var browserState = WorkingCopySplitBrowserState()
    @State private var loadingDirectoryGenerations: [String: Int] = [:]
    @State private var cacheGeneration = 0
    @State private var sortOrder = [KeyPathComparator(\WorkingCopySplitTableRow.name)]
    @FocusState private var focusedPanel: WorkingCopySplitBrowserState.FocusedPanel?

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            folderPanel
            Divider()
            contentsPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $store.isShowingFileHistory) {
            FileHistoryView().environment(store)
        }
        .task(id: store.selectedProjectID) {
            await prepareForSelectedProject()
        }
        .onChange(of: store.workingCopyBrowserRefreshGeneration) { _, _ in
            Task { await reloadCachedDirectories() }
        }
        .onChange(of: focusedPanel) { _, panel in
            guard let panel else { return }
            browserState.focusedPanel = panel
            synchronizeStoreSelection()
        }
        .documentOpenConfirmation()
    }

    private var folderPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(browserState.visibleFolderRows(rootName: rootFolderName)) { row in
                        folderRow(row)
                            .id(row.relativePath)
                    }
                }
            }
            .onChange(of: browserState.selectedFolderPath) { _, path in
                withAnimation { proxy.scrollTo(path, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground(for: .folders))
        .overlay {
            if loadingDirectoryGenerations[""] == cacheGeneration
                && !browserState.isDirectoryCached("") {
                ProgressView(appLanguage.localized("ui.loading.files.a3268fef"))
            }
        }
        .overlay { focusBorder(for: .folders) }
        .contentShape(Rectangle())
        .focusable()
        .focused($focusedPanel, equals: .folders)
        .simultaneousGesture(TapGesture().onEnded { focus(.folders) })
        .onKeyPress(keys: [.tab]) { press in
            moveFocus(reverse: press.modifiers.contains(.shift))
        }
        .onKeyPress(.upArrow) {
            moveFolderSelection(by: -1)
        }
        .onKeyPress(.downArrow) {
            moveFolderSelection(by: 1)
        }
        .onKeyPress(.rightArrow) {
            moveFolderRight()
        }
        .onKeyPress(.leftArrow) {
            browserState.moveFolderLeft()
            synchronizeFolderSelection()
            return .handled
        }
        .accessibilityLabel(appLanguage.localized("ui.folder.e6474408"))
    }

    private var contentsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(currentFolderDisplayPath)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(currentFolderDisplayPath)
                Spacer()
                Text(appLanguage.localized(
                    "ui.file.browser.items.count.86dc65fe",
                    sortedTableRows.count
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding()

            Divider()

            Table(sortedTableRows, selection: contentSelection, sortOrder: $sortOrder) {
                TableColumn(
                    appLanguage.localized("ui.file.browser.name.03fe9d71"),
                    value: \.name
                ) { row in
                    contextualCell(for: row.node) {
                        fileNameCell(row.node)
                    }
                    .onTapGesture(count: 2) {
                        Task { await activate(row.node) }
                    }
                }
                TableColumn(
                    appLanguage.localized("ui.file.browser.kind.98b7d2e4"),
                    value: \.kind
                ) { row in
                    contextualCell(for: row.node) {
                        Text(row.kind).lineLimit(1)
                    }
                }
                TableColumn(
                    appLanguage.localized("ui.file.browser.size.a77c1e02"),
                    value: \.fileSizeSortValue
                ) { row in
                    contextualCell(for: row.node) {
                        Text(fileSizeText(row.node)).monospacedDigit()
                    }
                }
                TableColumn(
                    appLanguage.localized("ui.file.browser.modified.date.6cb3548f"),
                    value: \.modificationDateSortValue
                ) { row in
                    contextualCell(for: row.node) {
                        Text(modificationDateText(row.node.modificationDate))
                            .monospacedDigit()
                    }
                }
                TableColumn(appLanguage.localized("ui.file.browser.actions.14f5c2a1")) { row in
                    contextualCell(for: row.node) {
                        rowActions(row.node)
                    }
                }
            }
            .overlay {
                if isLoadingCurrentDirectory && !browserState.isDirectoryCached(browserState.currentDirectoryPath) {
                    ProgressView(appLanguage.localized("ui.loading.files.a3268fef"))
                } else if browserState.isDirectoryCached(browserState.currentDirectoryPath)
                            && sortedTableRows.isEmpty {
                    ContentUnavailableView(
                        appLanguage.localized("ui.no.files.5245ffcc"),
                        systemImage: "folder"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground(for: .contents))
        .overlay { focusBorder(for: .contents) }
        .contentShape(Rectangle())
        .focusable()
        .focused($focusedPanel, equals: .contents)
        .simultaneousGesture(TapGesture().onEnded { focus(.contents) })
        .onKeyPress(keys: [.tab]) { press in
            moveFocus(reverse: press.modifiers.contains(.shift))
        }
        .onKeyPress(.upArrow) {
            moveContentSelection(by: -1)
        }
        .onKeyPress(.downArrow) {
            moveContentSelection(by: 1)
        }
        .onKeyPress(.return) {
            guard let node = selectedContentNode else { return .ignored }
            Task { await activate(node) }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            let previousDirectory = browserState.currentDirectoryPath
            browserState.moveToParentDirectory()
            guard browserState.currentDirectoryPath != previousDirectory else { return .handled }
            synchronizeFolderSelection()
            Task { await loadDirectory(browserState.currentDirectoryPath) }
            return .handled
        }
        .accessibilityLabel(appLanguage.localized("ui.files.6075adef"))
    }

    private func folderRow(_ row: WorkingCopySplitBrowserState.FolderRow) -> some View {
        HStack(spacing: 4) {
            if row.hasChildren {
                Button {
                    let pathToLoad = browserState.toggleFolderExpansion(row.relativePath)
                    if let pathToLoad {
                        Task { await loadDirectory(pathToLoad) }
                    }
                } label: {
                    Image(systemName: browserState.expandedDirectoryPaths.contains(row.relativePath)
                          ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right").hidden()
            }

            Button {
                browserState.selectFolder(row.relativePath)
                synchronizeFolderSelection()
                Task { await loadDirectory(row.relativePath) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.accentColor)
                    Text(row.name).lineLimit(1)
                    if let node = folderNode(at: row.relativePath),
                       let status = visibleStatus(for: node) {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            browserState.selectedFolderPath == row.relativePath
                ? Color.accentColor.opacity(0.18)
                : Color.clear
        )
        .contextMenu {
            if let node = folderNode(at: row.relativePath) {
                contextMenuItems(for: node)
            } else {
                Button(appLanguage.localized("ui.reveal.in.finder.52d4a206")) {
                    store.revealInFinder("")
                }
                Button(appLanguage.localized("ui.copy.full.path.823e26e7")) {
                    store.copyPath("")
                }
            }
        }
    }

    private func fileNameCell(_ node: WorkingCopyFileNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: node))
                .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
            Text(node.name).lineLimit(1)
            if let status = visibleStatus(for: node) {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let lock = lockInfo(for: node) {
                Label(lock.owner, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(
                        lock.owner == store.selectedProject?.username ? Color.accentColor : Color.orange
                    )
                    .help(lockDescription(lock))
            }
            if node.isSymbolicLink {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized("ui.symbolic.link.0dc00212"))
            }
        }
    }

    private func rowActions(_ node: WorkingCopyFileNode) -> some View {
        HStack {
            if !node.isDirectory {
                Button(appLanguage.localized("ui.open.file.ea89b4b3")) {
                    Task { await openFile(node) }
                }
            }
            Button(appLanguage.localized("ui.reveal.in.finder.52d4a206")) {
                store.revealInFinder(node.relativePath)
            }
        }
    }

    private func contextualCell<Content: View>(
        for node: WorkingCopyFileNode,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu { contextMenuItems(for: node) }
    }

    @ViewBuilder
    private func contextMenuItems(for node: WorkingCopyFileNode) -> some View {
        if !node.isDirectory {
            Button(appLanguage.localized("ui.open.file.ea89b4b3")) {
                Task { await openFile(node) }
            }
            if let lock = lockInfo(for: node),
               lock.owner == store.selectedProject?.username {
                Button(appLanguage.localized("ui.release.lock.695a2075")) {
                    Task { await store.unlock(lock) }
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
        }
        Button(appLanguage.localized("ui.reveal.in.finder.52d4a206")) {
            store.revealInFinder(node.relativePath)
        }
        Button(appLanguage.localized("ui.copy.full.path.823e26e7")) {
            store.copyPath(node.relativePath)
        }
        if !node.isDirectory, node.isVersioned {
            Divider()
            Button(appLanguage.localized("ui.file.commit.history.342bfaac")) {
                Task { await store.loadFileHistory(for: node.repositoryRelativePath) }
            }
        }
    }

    private var rootFolderName: String {
        store.selectedProject?.name ?? appLanguage.localized("ui.file.browser.working.copy.root.731fa805")
    }

    private var currentFolderDisplayPath: String {
        guard let rootPath = store.selectedProject?.path else { return "" }
        guard !browserState.currentDirectoryPath.isEmpty else { return rootPath }
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(browserState.currentDirectoryPath, isDirectory: true)
            .path
    }

    private var tableRows: [WorkingCopySplitTableRow] {
        browserState.currentDirectoryContents.map {
            WorkingCopySplitTableRow(node: $0, kind: kindDescription($0))
        }
    }

    private var sortedTableRows: [WorkingCopySplitTableRow] {
        tableRows.sorted(using: sortOrder)
    }

    private var sortedContentNodes: [WorkingCopyFileNode] {
        sortedTableRows.map(\.node)
    }

    private var selectedContentNode: WorkingCopyFileNode? {
        guard let path = browserState.selectedContentPath else { return nil }
        return browserState.currentDirectoryContents.first { $0.relativePath == path }
    }

    private var contentSelection: Binding<String?> {
        Binding(
            get: { browserState.selectedContentPath },
            set: { path in
                browserState.selectContent(path)
                if browserState.focusedPanel == .contents {
                    store.selectedBrowserPath = path
                }
            }
        )
    }

    private var isLoadingCurrentDirectory: Bool {
        loadingDirectoryGenerations[browserState.currentDirectoryPath] == cacheGeneration
    }

    private func panelBackground(
        for panel: WorkingCopySplitBrowserState.FocusedPanel
    ) -> Color {
        browserState.focusedPanel == panel
            ? Color.accentColor.opacity(0.05)
            : Color(nsColor: .controlBackgroundColor)
    }

    private func focusBorder(
        for panel: WorkingCopySplitBrowserState.FocusedPanel
    ) -> some View {
        Rectangle()
            .stroke(
                browserState.focusedPanel == panel ? Color.accentColor : Color.clear,
                lineWidth: 2
            )
            .allowsHitTesting(false)
    }

    private func focus(_ panel: WorkingCopySplitBrowserState.FocusedPanel) {
        browserState.focusedPanel = panel
        focusedPanel = panel
        synchronizeStoreSelection()
    }

    private func moveFocus(reverse: Bool) -> KeyPress.Result {
        browserState.moveFocus(reverse: reverse)
        focusedPanel = browserState.focusedPanel
        synchronizeStoreSelection()
        return .handled
    }

    private func moveFolderSelection(by offset: Int) -> KeyPress.Result {
        browserState.moveFolderSelection(by: offset, rootName: rootFolderName)
        synchronizeFolderSelection()
        return .handled
    }

    private func moveFolderRight() -> KeyPress.Result {
        let previousSelection = browserState.selectedFolderPath
        let pathToLoad = browserState.moveFolderRight()
        if browserState.selectedFolderPath != previousSelection {
            synchronizeFolderSelection()
        }
        if let pathToLoad {
            Task { await loadDirectory(pathToLoad) }
        }
        return .handled
    }

    private func moveContentSelection(by offset: Int) -> KeyPress.Result {
        browserState.moveContentSelection(by: offset, in: sortedContentNodes)
        store.selectedBrowserPath = browserState.selectedContentPath
        return .handled
    }

    private func synchronizeFolderSelection() {
        store.selectedBrowserPath = browserState.selectedFolderPath.isEmpty
            ? nil
            : browserState.selectedFolderPath
        Task { await loadDirectory(browserState.currentDirectoryPath) }
    }

    private func synchronizeStoreSelection() {
        switch browserState.focusedPanel {
        case .folders:
            store.selectedBrowserPath = browserState.selectedFolderPath.isEmpty
                ? nil
                : browserState.selectedFolderPath
        case .contents:
            store.selectedBrowserPath = browserState.selectedContentPath
        }
    }

    private func activate(_ node: WorkingCopyFileNode) async {
        if node.isDirectory {
            browserState.enterDirectory(node.relativePath)
            synchronizeFolderSelection()
            await loadDirectory(node.relativePath)
        } else {
            await openFile(node)
        }
    }

    private func openFile(_ node: WorkingCopyFileNode) async {
        await store.prepareToOpen(
            path: node.relativePath,
            repositoryPath: node.repositoryRelativePath,
            isVersioned: node.isVersioned,
            isRegularFile: node.isRegularFile
        )
    }

    private func prepareForSelectedProject() async {
        cacheGeneration &+= 1
        loadingDirectoryGenerations.removeAll()
        browserState = WorkingCopySplitBrowserState()
        await loadDirectory("")
        await restoreStoreSelectionIfPossible()
        focus(.folders)
    }

    private func reloadCachedDirectories() async {
        let directoriesToReload = browserState.expandedDirectoryPaths
            .union([browserState.currentDirectoryPath])
            .sorted { directoryDepth($0) < directoryDepth($1) }
        cacheGeneration &+= 1
        loadingDirectoryGenerations.removeAll()
        browserState.clearCacheForRefresh()
        for directory in directoriesToReload {
            await loadDirectory(directory)
        }
    }

    private func loadDirectory(_ relativeDirectory: String) async {
        guard !browserState.isDirectoryCached(relativeDirectory),
              loadingDirectoryGenerations[relativeDirectory] != cacheGeneration else { return }
        let requestedGeneration = cacheGeneration
        loadingDirectoryGenerations[relativeDirectory] = requestedGeneration
        let contents = await store.loadWorkingCopyDirectoryContents(at: relativeDirectory)
        if loadingDirectoryGenerations[relativeDirectory] == requestedGeneration {
            loadingDirectoryGenerations[relativeDirectory] = nil
        }
        guard requestedGeneration == cacheGeneration, let contents else { return }
        browserState.cache(contents, for: relativeDirectory)
    }

    private func restoreStoreSelectionIfPossible() async {
        guard let selectedPath = store.selectedBrowserPath, !selectedPath.isEmpty else { return }
        let components = selectedPath.split(separator: "/").map(String.init)
        var parent = ""
        for component in components {
            await loadDirectory(parent)
            let childPath = parent.isEmpty ? component : "\(parent)/\(component)"
            guard let node = browserState.directoryContentsByPath[parent]?
                .first(where: { $0.relativePath == childPath }) else { return }
            if node.isDirectory {
                browserState.enterDirectory(childPath)
                parent = childPath
            } else {
                browserState.enterDirectory(parent)
                browserState.selectContent(childPath)
                return
            }
        }
        await loadDirectory(browserState.currentDirectoryPath)
    }

    private func folderNode(at relativePath: String) -> WorkingCopyFileNode? {
        guard !relativePath.isEmpty else { return nil }
        let parent = WorkingCopySplitBrowserState.parentDirectory(of: relativePath) ?? ""
        return browserState.folderChildren(of: parent)
            .first { $0.relativePath == relativePath }
    }

    private func directoryDepth(_ relativePath: String) -> Int {
        relativePath.isEmpty ? 0 : relativePath.split(separator: "/").count
    }

    private func kindDescription(_ node: WorkingCopyFileNode) -> String {
        node.typeDescription ?? appLanguage.localized(
            node.isDirectory ? "ui.folder.e6474408" : "ui.file.811b7680"
        )
    }

    private func fileSizeText(_ node: WorkingCopyFileNode) -> String {
        guard !node.isDirectory, let fileSize = node.fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    private func modificationDateText(_ date: Date?) -> String {
        guard let date else { return "" }
        // 파일 메타데이터는 커밋 표시 설정을 거치지 않고 현재 파일시스템 로컬 시각으로 표시합니다.
        return date.formatted(Date.FormatStyle(
            date: .numeric,
            time: .shortened,
            locale: .autoupdatingCurrent,
            calendar: .autoupdatingCurrent,
            timeZone: .autoupdatingCurrent
        ))
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
        case "modified": return appLanguage.localized("ui.modified.01365bb2")
        case "added": return appLanguage.localized("ui.added.0dce7328")
        case "unversioned": return appLanguage.localized("ui.unversioned.ffbcbcb7")
        case "ignored": return appLanguage.localized("ui.ignored.b45ee0ef")
        case "conflicted": return appLanguage.localized("ui.conflict.37edb628")
        default: return status
        }
    }

    private func lockInfo(for node: WorkingCopyFileNode) -> SVNLockInfo? {
        store.repositoryLocks.first { node.matchesRepositoryPath($0.path) }
    }

    private func lockDescription(_ lock: SVNLockInfo) -> String {
        if lock.owner == store.selectedProject?.username {
            return appLanguage.localized("ui.locked.by.you.f2a7c3f2")
        }
        return appLanguage.localized("ui.locked.by.192b78cf", lock.owner)
    }
}

private struct WorkingCopySplitTableRow: Identifiable {
    let node: WorkingCopyFileNode
    let kind: String

    var id: String { node.relativePath }
    var name: String { node.name }
    var fileSizeSortValue: Int { node.isDirectory ? -1 : node.fileSize ?? -1 }
    var modificationDateSortValue: TimeInterval {
        node.modificationDate?.timeIntervalSinceReferenceDate ?? -.infinity
    }
}
