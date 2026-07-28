import SwiftUI
import SVNCore

struct WorkingCopyBrowserView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Binding var searchText: String

    var body: some View {
        List(selection: $store.selectedBrowserPath) {
            OutlineGroup(filteredTree, children: \.children) { node in
                fileRow(node)
                    .tag(node.relativePath)
            }
        }
        .overlay {
            if isLoading, store.workingCopyFileTree.isEmpty {
                ProgressView(appLanguage.text("파일 목록을 불러오는 중…", "Loading files…"))
            } else if filteredTree.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty
                        ? appLanguage.text("표시할 파일 없음", "No Files")
                        : appLanguage.text("검색 결과 없음", "No Search Results"),
                    systemImage: searchText.isEmpty ? "folder" : "magnifyingglass"
                )
            }
        }
        .sheet(isPresented: $store.isShowingFileHistory) {
            FileHistoryView().environmentObject(store)
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
                    .help(appLanguage.text("심볼릭 링크", "Symbolic Link"))
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
        .contextMenu {
            if !node.isDirectory {
                Button(appLanguage.text("파일 열기", "Open File")) {
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
                    Button(appLanguage.text("잠금 해제", "Release Lock")) {
                        Task { await store.unlock(lock) }
                    }
                    .disabled(store.isWorking)
                }
            }
            Button(appLanguage.text("Finder에서 보기", "Reveal in Finder")) {
                store.revealInFinder(node.relativePath)
            }
            Button(appLanguage.text("전체 경로 복사", "Copy Full Path")) {
                store.copyPath(node.relativePath)
            }
            if !node.isDirectory, node.isVersioned {
                Divider()
                Button(appLanguage.text("이 파일의 커밋 기록", "File Commit History")) {
                    Task { await store.loadFileHistory(for: node.repositoryRelativePath) }
                }
            }
        }
    }

    private var filteredTree: [WorkingCopyFileNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.workingCopyFileTree }
        return store.workingCopyFileTree.compactMap { $0.filtering(query: query) }
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
        case "modified": return appLanguage.text("수정", "Modified")
        case "added": return appLanguage.text("추가", "Added")
        case "unversioned": return appLanguage.text("미추적", "Unversioned")
        case "ignored": return appLanguage.text("무시됨", "Ignored")
        case "conflicted": return appLanguage.text("충돌", "Conflict")
        default: return status
        }
    }

    private func lockInfo(for node: WorkingCopyFileNode) -> SVNLockInfo? {
        store.repositoryLocks.first { node.matchesRepositoryPath($0.path) }
    }

    private func lockDescription(_ lock: SVNLockInfo) -> String {
        if lock.owner == store.selectedProject?.username {
            return appLanguage.text("내가 잠근 파일", "Locked by you")
        }
        return appLanguage.text("\(lock.owner) 사용자가 잠근 파일", "Locked by \(lock.owner)")
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
