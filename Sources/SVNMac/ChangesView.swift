import SwiftUI
import SVNCore

/// 변경 파일 선택, diff 확인, 선택 커밋 입력을 담당하는 전용 화면입니다.
/// 커밋 입력 상태를 이 화면 안에 두어 ContentView가 탭 내부 동작을 알 필요가 없게 합니다.
struct ChangesView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage

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
                CommitControlsView()
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
        .sheet(isPresented: $store.isShowingIgnoreRules) {
            IgnoreRulesView()
                .environmentObject(store)
        }
        .sheet(item: $store.activeConflictSession) { _ in
            ConflictResolutionView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingFileHistory) {
            FileHistoryView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isShowingPathRecovery) {
            WorkingCopyRecoveryView()
                .environmentObject(store)
        }
        .revertConfirmation()
        .documentOpenConfirmation()
    }

    // MARK: - 변경 파일 목록

    private var changedFileList: some View {
        List {
            ForEach(store.pathCollisions) { collision in
                collisionRow(collision)
            }
            ForEach(store.statuses) { entry in
                changedFileRow(entry)
            }
            if store.showsIgnoredFiles {
                ForEach(store.ignoredStatuses) { entry in
                    changedFileRow(entry)
                }
            }
        }
        .overlay {
            if store.pathCollisions.isEmpty && store.statuses.isEmpty && (!store.showsIgnoredFiles || store.ignoredStatuses.isEmpty) {
                ContentUnavailableView(
                    appLanguage.text("변경 사항 없음", "No Changes"),
                    systemImage: "checkmark.circle",
                    description: Text(appLanguage.text("로컬에서 수정된 파일이 없습니다.", "There are no locally modified files."))
                )
            }
        }
    }

    private func changedFileRow(_ entry: SVNStatusEntry) -> some View {
        HStack {
            if entry.isSelectableForCommit {
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
            statusBadge(entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path.precomposedStringWithCanonicalMapping).lineLimit(1)
                if entry.item == .unversioned && entry.nodeKind == .directory {
                    Text(appLanguage.text(
                        "하위 파일이 함께 추가됩니다.",
                        "Files inside this folder will be added together."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
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
                            && entry.item != .added,
                        isRegularFile: entry.nodeKind == .file
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

    private func collisionRow(_ collision: SVNPathCollision) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text(appLanguage.text("한글 경로 충돌", "Unicode Path Conflict"))
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.orange, in: Capsule())
            Text(collision.displayPath).lineLimit(1)
            Spacer()
            Text(appLanguage.text("\(collision.affectedEntryCount)개 영향", "\(collision.affectedEntryCount) affected"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if collision.id == store.pathCollisions.first?.id {
                if store.canRepairCanonicalAliases {
                    Button(appLanguage.text("동일 한글 경로 정리", "Clean Up Equivalent Path")) {
                        Task { await store.repairCanonicalAliases() }
                    }
                    .disabled(store.isWorking)
                } else {
                    Text(appLanguage.text(
                        "서버 중복 경로 수동 정리 필요",
                        "Resolve Duplicate Server Paths Manually"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(appLanguage.text(
                        "정규화하면 같은 서버 경로가 둘 이상이어서 앱이 기준 경로를 선택할 수 없습니다.",
                        "Multiple canonically equivalent server paths exist, so the app cannot choose one safely."
                    ))
                }
            }
        }
    }

    private var changesToolbar: some View {
        HStack {
            Toggle(appLanguage.text("무시된 파일 보기", "Show Ignored Files"), isOn: Binding(
                get: { store.showsIgnoredFiles },
                set: { value in Task { await store.setShowsIgnoredFiles(value) } }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Spacer()
            Button(appLanguage.text("무시 규칙 관리", "Manage Ignore Rules"), systemImage: "eye.slash") {
                Task {
                    await store.loadIgnoreRules()
                    store.isShowingIgnoreRules = true
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 변경 상태 배지

    private func statusBadge(_ entry: SVNStatusEntry) -> some View {
        Text(statusLabel(entry))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor(entry), in: Capsule())
    }

    private func statusLabel(_ entry: SVNStatusEntry) -> String {
        if entry.isTemporaryFile {
            return appLanguage.text("임시파일", "Temporary")
        }
        return switch entry.item {
        case .modified: appLanguage.text("수정", "Modified")
        case .added: appLanguage.text("추가", "Added")
        case .deleted: appLanguage.text("삭제", "Deleted")
        case .missing where entry.isMissingScheduledAddition: appLanguage.text("정리 필요", "Cleanup Needed")
        case .missing: appLanguage.text("로컬 누락", "Locally Missing")
        case .unversioned: appLanguage.text("미추적", "Unversioned")
        case .ignored: appLanguage.text("무시됨", "Ignored")
        case .conflicted: appLanguage.text("충돌", "Conflict")
        case .replaced: appLanguage.text("교체", "Replaced")
        case let .unknown(value): value
        }
    }

    private func statusColor(_ entry: SVNStatusEntry) -> Color {
        if entry.isTemporaryFile { return .gray }
        return switch entry.item {
        case .modified: .orange
        case .added, .unversioned: .blue
        case .ignored: .gray
        case .missing where entry.isMissingScheduledAddition: .gray
        case .deleted, .missing, .conflicted: .red
        default: .gray
        }
    }
}
