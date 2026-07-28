import SwiftUI
import SVNCore

struct WorkingCopyBrowserView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Binding var searchText: String
    @State private var filteredSearchTree: [WorkingCopyFileNode] = []

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedBrowserPath) {
            OutlineGroup(displayedTree, children: \.children) { node in
                fileRow(node)
                    .tag(node.relativePath)
            }
        }
        .overlay {
            if isLoading, store.workingCopyFileTree.isEmpty {
                ProgressView(appLanguage.localized("ui.loading.files.a3268fef"))
            } else if displayedTree.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty
                        ? appLanguage.localized("ui.no.files.5245ffcc")
                        : appLanguage.localized("ui.no.search.results.e40b4a06"),
                    systemImage: searchText.isEmpty ? "folder" : "magnifyingglass"
                )
            }
        }
        .sheet(isPresented: $store.isShowingFileHistory) {
            FileHistoryView().environment(store)
        }
        .task(id: FileTreeFilterInput(tree: store.workingCopyFileTree, query: searchText)) {
            let input = FileTreeFilterInput(tree: store.workingCopyFileTree, query: searchText)
            filteredSearchTree = await Task.detached {
                input.filteredTree
            }.value
        }
        .documentOpenConfirmation()
    }

    private func fileRow(_ node: WorkingCopyFileNode) -> some View {
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
            if let lock = lockInfo(for: node) {
                Label(lock.owner, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(lock.owner == store.selectedProject?.username ? Color.accentColor : Color.orange)
                    .help(lockDescription(lock))
            }
            if node.isSymbolicLink {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized("ui.symbolic.link.0dc00212"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
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
        .accessibilityAction(named: appLanguage.localized("ui.open.file.ea89b4b3")) {
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
        .contextMenu {
            if !node.isDirectory {
                Button(appLanguage.localized("ui.open.file.ea89b4b3")) {
                    Task {
                        await store.prepareToOpen(
                            path: node.relativePath,
                            repositoryPath: node.repositoryRelativePath,
                            isVersioned: node.isVersioned,
                            isRegularFile: node.isRegularFile
                        )
                    }
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
    }

    private var displayedTree: [WorkingCopyFileNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.workingCopyFileTree }
        return filteredSearchTree
    }

    private var isLoading: Bool {
        guard let projectID = store.selectedProjectID else { return false }
        return store.activeOperations.contains { $0.kind == .browseFiles(projectID) }
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

private struct FileTreeFilterInput: Hashable, Sendable {
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
            svnEntry: svnEntry,
            children: filteredChildren
        )
    }
}
