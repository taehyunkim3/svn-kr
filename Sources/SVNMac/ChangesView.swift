import SwiftUI
import SVNCore

/// 변경 파일 선택, diff 확인, 선택 커밋 입력을 담당하는 전용 화면입니다.
/// 커밋 입력 상태를 이 화면 안에 두어 ContentView가 탭 내부 동작을 알 필요가 없게 합니다.
struct ChangesView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var commitMessage = ""
    @FocusState private var isCommitMessageFocused: Bool

    var body: some View {
        WorkspaceSplitView(
            primaryMinWidth: AppLayout.changesPrimaryMinimumWidth,
            detailMinWidth: AppLayout.changesDetailMinimumWidth
        ) {
            VStack(spacing: 0) {
                changesToolbar
                Divider()
                changedFileList
                Divider()
                commitControls
            }
        } detail: {
            ScrollView([.horizontal, .vertical]) {
                Text(store.diffContent.localizedText(appLanguage))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
            // 배경보다 먼저 전체 크기를 확정해야 빈 diff와 긴 diff가 같은 패널 크기를 사용합니다.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onChange(of: store.lastCompletedCommitMessage) { _, message in
            guard message != nil else { return }
            // 직접 커밋과 인증 후 재개된 커밋 모두 이 완료 이벤트 하나로 입력을 비웁니다.
            commitMessage = ""
            isCommitMessageFocused = false
            store.lastCompletedCommitMessage = nil
        }
        .sheet(isPresented: $store.isShowingIgnoreRules) {
            IgnoreRulesView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingLocks) {
            RepositoryLocksView()
                .environmentObject(store)
        }
        .sheet(item: $store.activeConflict) { _ in
            ConflictResolutionView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingFileHistory) {
            FileHistoryView()
                .environmentObject(store)
        }
        .revertConfirmation()
        .documentOpenConfirmation()
    }

    // MARK: - 변경 파일 목록

    private var changedFileList: some View {
        List(displayedStatuses) { entry in
            HStack {
                if entry.item != .ignored && entry.item != .conflicted {
                    Toggle("", isOn: Binding(
                        get: { store.selectedPaths.contains(entry.path) },
                        set: { checked in
                            if checked { store.selectedPaths.insert(entry.path) }
                            else { store.selectedPaths.remove(entry.path) }
                        }
                    ))
                    .labelsHidden()
                    .help(appLanguage.text("이 파일을 다음 선택 커밋에 포함하거나 제외합니다.", "Include or exclude this file from the next commit."))
                } else {
                    Image(systemName: "eye.slash").frame(width: 18)
                }
                statusBadge(entry.item)
                Text(entry.path).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await store.loadDiff(for: entry.path) } }
            .listRowBackground(store.selectedStatusPath == entry.path ? Color.accentColor.opacity(0.12) : Color.clear)
            .contextMenu {
                Button(appLanguage.text("파일 열기", "Open File")) {
                    Task {
                        await store.prepareToOpen(
                            path: entry.path,
                            isVersioned: entry.item != .unversioned
                                && entry.item != .ignored
                                && entry.item != .added
                        )
                    }
                }
                Button(appLanguage.text("Finder에서 보기", "Reveal in Finder")) {
                    store.revealInFinder(entry.path)
                }
                Button(appLanguage.text("전체 경로 복사", "Copy Full Path")) {
                    store.copyPath(entry.path)
                }
                if entry.item != .unversioned && entry.item != .ignored && entry.item != .added {
                    Button(appLanguage.text("이 파일의 커밋 기록", "File Commit History")) {
                        Task { await store.loadFileHistory(for: entry.path) }
                    }
                }
                Divider()
                if entry.item == .conflicted {
                    Button(appLanguage.text("충돌 해결…", "Resolve Conflict…")) {
                        Task { await store.prepareConflictResolution(for: entry.path) }
                    }
                    Divider()
                }
                if entry.item == .unversioned {
                    Button(appLanguage.text("이 파일 무시", "Ignore This Item")) {
                        Task { await store.ignore(path: entry.path, byExtension: false) }
                    }
                    if !(entry.path as NSString).pathExtension.isEmpty {
                        Button(appLanguage.text("같은 확장자 모두 무시", "Ignore This Extension")) {
                            Task { await store.ignore(path: entry.path, byExtension: true) }
                        }
                    }
                }
                if entry.item != .unversioned && entry.item != .ignored && entry.item != .conflicted {
                    Divider()
                    Button(appLanguage.text("로컬 변경 되돌리기…", "Revert Local Changes…"), role: .destructive) {
                        store.requestRevert(entry)
                    }
                }
            }
        }
        .overlay {
            if displayedStatuses.isEmpty {
                ContentUnavailableView(
                    appLanguage.text("변경 사항 없음", "No Changes"),
                    systemImage: "checkmark.circle",
                    description: Text(appLanguage.text("로컬에서 수정된 파일이 없습니다.", "There are no locally modified files."))
                )
            }
        }
    }

    private var displayedStatuses: [SVNStatusEntry] {
        store.statuses + (store.showsIgnoredFiles ? store.ignoredStatuses : [])
    }

    private var changesToolbar: some View {
        HStack {
            Toggle(appLanguage.text("무시된 파일 보기", "Show Ignored Files"), isOn: Binding(
                get: { store.showsIgnoredFiles },
                set: { value in Task { await store.setShowsIgnoredFiles(value) } }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button(appLanguage.text("무시 규칙 관리", "Manage Ignore Rules"), systemImage: "eye.slash") {
                Task {
                    await store.loadIgnoreRules()
                    store.isShowingIgnoreRules = true
                }
            }
            .buttonStyle(.borderless)
            Button(appLanguage.text("잠금 목록", "Locks"), systemImage: "lock") {
                Task {
                    await store.loadRepositoryLocks()
                    store.isShowingLocks = true
                }
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 커밋 입력과 실행

    private var commitControls: some View {
        VStack(spacing: 8) {
            TextField(appLanguage.text("커밋 메시지", "Commit message"), text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .focused($isCommitMessageFocused)
                .onSubmit { submitCommitAfterEndingTextInput() }
            HStack {
                Button(appLanguage.text("전체 선택", "Select All")) {
                    store.selectedPaths = Set(store.statuses.map(\.path))
                }
                .help(appLanguage.text("현재 변경된 파일을 모두 커밋 대상으로 선택합니다.", "Select all currently changed files for commit."))
                Button(appLanguage.text("선택 해제", "Clear Selection")) { store.selectedPaths.removeAll() }
                    .help(appLanguage.text("현재 선택된 커밋 대상을 모두 해제합니다.", "Clear all selected commit targets."))
                Spacer()
                Text(appLanguage.text("\(store.selectedPaths.count)개 선택", "\(store.selectedPaths.count) selected"))
                    .foregroundStyle(.secondary)
                Button(appLanguage.text("선택 항목 커밋", "Commit Selected")) { submitCommitAfterEndingTextInput() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedPaths.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                    .help(appLanguage.text("선택한 파일을 입력한 메시지로 SVN 서버에 커밋합니다.", "Commit the selected files to the SVN server with the entered message."))
            }
        }
        .padding()
    }

    private func submitCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        Task { _ = await store.commit(message: message) }
    }

    private func submitCommitAfterEndingTextInput() {
        isCommitMessageFocused = false
        Task { @MainActor in
            // macOS TextField가 조합 중인 한글을 binding에 반영한 다음 메시지를 읽습니다.
            await Task.yield()
            submitCommit()
        }
    }

    // MARK: - 변경 상태 배지

    private func statusBadge(_ item: SVNStatusKind) -> some View {
        Text(statusLabel(item))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor(item), in: Capsule())
    }

    private func statusLabel(_ item: SVNStatusKind) -> String {
        switch item {
        case .modified: appLanguage.text("수정", "Modified")
        case .added: appLanguage.text("추가", "Added")
        case .deleted, .missing: appLanguage.text("삭제", "Deleted")
        case .unversioned: appLanguage.text("미추적", "Unversioned")
        case .ignored: appLanguage.text("무시됨", "Ignored")
        case .conflicted: appLanguage.text("충돌", "Conflict")
        case .replaced: appLanguage.text("교체", "Replaced")
        case let .unknown(value): value
        }
    }

    private func statusColor(_ item: SVNStatusKind) -> Color {
        switch item {
        case .modified: .orange
        case .added, .unversioned: .blue
        case .ignored: .gray
        case .deleted, .missing, .conflicted: .red
        default: .gray
        }
    }
}
