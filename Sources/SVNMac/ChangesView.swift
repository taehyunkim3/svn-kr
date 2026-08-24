import SwiftUI
import SVNCore

/// 변경 파일 선택, diff 확인, 선택 커밋 입력을 담당하는 전용 화면입니다.
/// 커밋 입력 상태를 이 화면 안에 두어 ContentView가 탭 내부 동작을 알 필요가 없게 합니다.
struct ChangesView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        @Bindable var store = store
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
                .environment(store)
        }
        .sheet(item: $store.activeConflictSession) { _ in
            ConflictResolutionView()
                .environment(store)
        }
        .sheet(isPresented: $store.isShowingFileHistory) {
            FileHistoryView()
                .environment(store)
        }
        .sheet(isPresented: $store.isShowingPathRecovery) {
            WorkingCopyRecoveryView()
                .environment(store)
        }
        .sheet(item: $store.deletionRequest) { request in
            DeletionConfirmationView(request: request)
                .environment(store)
        }
        .revertConfirmation()
        .documentOpenConfirmation()
    }

    // MARK: - 변경 파일 목록

    private var changedFileList: some View {
        let visibleStatuses = store.visibleStatuses
        let visibleIgnoredStatuses = store.visibleIgnoredStatuses

        return List {
            ForEach(store.pathCollisions) { collision in
                collisionRow(collision)
            }
            ForEach(visibleStatuses) { entry in
                changedFileRow(entry)
            }
            if store.showsIgnoredFiles {
                ForEach(visibleIgnoredStatuses) { entry in
                    changedFileRow(entry)
                }
            }
        }
        .overlay {
            if store.pathCollisions.isEmpty && visibleStatuses.isEmpty && (!store.showsIgnoredFiles || visibleIgnoredStatuses.isEmpty) {
                ContentUnavailableView(
                    appLanguage.localized("ui.no.changes.ea917fd6"),
                    systemImage: "checkmark.circle",
                    description: Text(appLanguage.localized("ui.there.are.no.locally.modified.files.8560ad60"))
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
                .accessibilityLabel(appLanguage.localized("ui.include.in.commit.2aaaa224", entry.path))
                .help(appLanguage.localized("ui.include.or.exclude.this.file.from.the.next.commi.273bb38e"))
            } else if entry.canScheduleRepositoryDeletion {
                Menu {
                    Button(appLanguage.localized("ui.restore.local.file.b40bfb4b")) {
                        store.requestRevert(entry)
                    }
                    Button(appLanguage.localized("ui.delete.from.repository.deb8c2a7"), role: .destructive) {
                        store.requestDeletion(entry)
                    }
                } label: {
                    Label(appLanguage.localized("ui.choose.action.60c39cbd"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Image(systemName: "eye.slash").frame(width: 18)
            }
            statusBadge(entry)
            Button {
                Task { await store.loadDiff(for: entry.path) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.path.precomposedStringWithCanonicalMapping).lineLimit(1)
                    if entry.item == .unversioned && entry.nodeKind == .directory {
                        Text(appLanguage.localized("ui.files.inside.this.folder.will.be.added.together.637444b8"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(appLanguage.localized("ui.shows.the.diff.for.this.file.6f52b16a"))
            Spacer()
        }
        .listRowBackground(store.selectedStatusPath == entry.path ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            Button(appLanguage.localized("ui.open.file.ea89b4b3")) {
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
            Button(appLanguage.localized("ui.reveal.in.finder.52d4a206")) {
                store.revealInFinder(entry.path)
            }
            Button(appLanguage.localized("ui.copy.full.path.823e26e7")) {
                store.copyPath(entry.path)
            }
            if entry.item != .unversioned && entry.item != .ignored && entry.item != .added {
                Button(appLanguage.localized("ui.file.commit.history.342bfaac")) {
                    Task { await store.loadFileHistory(for: entry.path) }
                }
            }
            Divider()
            if entry.item == .conflicted {
                Button(appLanguage.localized("ui.resolve.conflict.592b6d3a")) {
                    Task { await store.prepareConflictResolution(for: entry.path) }
                }
                Divider()
            }
            if entry.item == .unversioned {
                Button(appLanguage.localized("ui.ignore.this.item.67c56906")) {
                    Task { await store.ignore(path: entry.path, byExtension: false) }
                }
                if !(entry.path as NSString).pathExtension.isEmpty {
                    Button(appLanguage.localized("ui.ignore.this.extension.687c5df7")) {
                        Task { await store.ignore(path: entry.path, byExtension: true) }
                    }
                }
            }
            if entry.canScheduleRepositoryDeletion {
                Divider()
                Button(appLanguage.localized("ui.restore.local.file.b40bfb4b")) {
                    store.requestRevert(entry)
                }
                Button(appLanguage.localized("ui.delete.from.repository.deb8c2a7"), role: .destructive) {
                    store.requestDeletion(entry)
                }
            }
            if entry.item != .unversioned && entry.item != .ignored && entry.item != .conflicted && entry.item != .missing {
                Divider()
                Button(
                    entry.item == .deleted
                        ? appLanguage.localized("ui.cancel.deletion.and.restore.ce07fc64")
                        : appLanguage.localized("ui.revert.local.changes.c62907ae"),
                    role: .destructive
                ) {
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
            StatusBadge(
                label: appLanguage.localized("ui.unicode.path.conflict.1ea3bdc6"),
                color: .orange
            )
            Text(collision.displayPath).lineLimit(1)
            Spacer()
            Text(appLanguage.localized("ui.affected.dbd64ef9", collision.affectedEntryCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            if collision.id == store.pathCollisions.first?.id {
                if store.canRepairCanonicalAliases {
                    Button {
                        Task { await store.repairCanonicalAliases() }
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized("ui.clean.up.equivalent.path.11fce14e"),
                            isInProgress: store.isRecoveringSelectedProject
                        )
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                } else {
                    Text(appLanguage.localized("ui.resolve.duplicate.server.paths.manually.e8b5d352"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized("ui.multiple.canonically.equivalent.server.paths.exi.55798f96"))
                }
            }
        }
    }

    private var changesToolbar: some View {
        HStack {
            Toggle(appLanguage.localized("ui.show.ignored.files.508dbd97"), isOn: Binding(
                get: { store.showsIgnoredFiles },
                set: { value in Task { await store.setShowsIgnoredFiles(value) } }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            let missingEntries = store.visibleStatuses.filter(\.canScheduleRepositoryDeletion)
            if missingEntries.count > 1 {
                Button {
                    store.requestDeletion(missingEntries)
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.delete.missing.items.ab0ea8fc", missingEntries.count),
                        systemImage: "trash",
                        isInProgress: store.isDeletingSelectedProject
                    )
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
            Spacer()
            Button(appLanguage.localized("ui.manage.ignore.rules.7eac76b1"), systemImage: "eye.slash") {
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
        StatusBadge(label: statusLabel(entry), color: statusColor(entry))
    }

    private func statusLabel(_ entry: SVNStatusEntry) -> String {
        if TemporaryFilePolicy.isTemporaryFile(entry) {
            return appLanguage.localized("ui.temporary.5738ffab")
        }
        return switch entry.item {
        case .modified: appLanguage.localized("ui.modified.01365bb2")
        case .added: appLanguage.localized("ui.added.0dce7328")
        case .deleted: appLanguage.localized("ui.pending.deletion.1652cca1")
        case .missing where entry.isMissingScheduledAddition: appLanguage.localized("ui.cleanup.needed.3c5f4e64")
        case .missing: appLanguage.localized("ui.locally.missing.action.required.50c49ccb")
        case .unversioned: appLanguage.localized("ui.unversioned.ffbcbcb7")
        case .ignored: appLanguage.localized("ui.ignored.b45ee0ef")
        case .conflicted: appLanguage.localized("ui.conflict.37edb628")
        case .replaced: appLanguage.localized("ui.replaced.6da39732")
        case let .unknown(value): value
        }
    }

    private func statusColor(_ entry: SVNStatusEntry) -> Color {
        if TemporaryFilePolicy.isTemporaryFile(entry) { return .gray }
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
