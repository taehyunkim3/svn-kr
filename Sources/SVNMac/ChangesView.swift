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
        .sheet(item: $store.activeTreeConflictSession) { _ in
            TreeConflictResolutionView()
                .environment(store)
        }
        .sheet(item: $store.recoveryState.propertyConflictSession) { _ in
            PropertyConflictResolutionView()
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
        .sheet(item: $store.recoveryState.versionedFileActionRequest) { request in
            VersionedFileActionView(request: request)
                .environment(store)
        }
        .task(id: versionedFilePaths) {
            await store.loadNeedsLockState(for: versionedFilePaths)
        }
        .task(id: store.selectedProjectID) {
            await store.loadSelectedRepositoryURL()
        }
        .onChange(of: store.errorMessage) { _, message in
            guard let message, SVNClient.isRepositoryConnectionError(message) else { return }
            Task { await store.captureRepositoryConnectionError(message) }
        }
        .revertConfirmation()
        .commitDeletionRestoreConfirmation()
        .documentOpenConfirmation()
        .explicitLockConfirmation()
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
                    appLanguage.localized(.ui.no.changes),
                    systemImage: "checkmark.circle",
                    description: Text(appLanguage.localized(.ui.there.areNoLocallyModifiedFiles))
                )
            }
        }
    }

    private func changedFileRow(_ entry: SVNStatusEntry) -> some View {
        HStack {
            if entry.isSelectableForCommit || entry.canScheduleRepositoryDeletion {
                Toggle("", isOn: Binding(
                    get: { store.selectedPaths.contains(entry.path) },
                    set: { checked in
                        if checked { store.selectedPaths.insert(entry.path) }
                        else { store.selectedPaths.remove(entry.path) }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel(appLanguage.localized(.ui.include.inCommit, entry.path))
                .help(appLanguage.localized(.ui.include.orExcludeThisFileFromTheNextCommi))
            } else {
                Image(systemName: "eye.slash").frame(width: 18)
            }
            statusBadge(entry)
            if WorkingCopyStatusPolicy.showsSwitchedWarning(entry) {
                StatusBadge(
                    label: appLanguage.localized(.ui.switched.path),
                    color: WorkingCopyStatusTone.purple.color,
                    style: .tinted
                )
                .help(appLanguage.localized(.ui.switched.pathCommitWarning))
            }
            if store.recoveryState.needsLockPaths.contains(entry.path) {
                Image(systemName: "lock.square")
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized(.ui.needs.lockEnabled))
            }
            if let lock = lockInfo(for: entry) {
                Label(lock.owner, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(
                        lock.owner == store.selectedProject?.username ? Color.accentColor : Color.orange
                    )
                    .help(lockDescription(lock))
            }
            Button {
                Task { await store.loadDiff(for: entry.path) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.path.precomposedStringWithCanonicalMapping).lineLimit(1)
                    if entry.item == .unversioned && entry.nodeKind == .directory {
                        Text(appLanguage.localized(.ui.files.insideThisFolderWillBeAddedTogether))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if WorkingCopyStatusPolicy.showsObstructionGuidance(entry) {
                        Text(appLanguage.localized(.ui.move.orRenameTheLocalFileThenUpdate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if WorkingCopyStatusPolicy.showsIncompleteRecovery(entry) {
                        Text(appLanguage.localized(.ui.localizationContinue.incompleteByUpdating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(appLanguage.localized(.ui.shows.theDiffForThisFile))
            Spacer()
            if entry.item == .obstructed {
                Button(appLanguage.localized(.ui.reveal.inFinder)) {
                    store.revealInFinder(entry.path)
                }
            } else if WorkingCopyStatusPolicy.showsIncompleteRecovery(entry) {
                Button(appLanguage.localized(.ui.localizationContinue.update)) {
                    Task { await store.update() }
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
        }
        .listRowBackground(store.selectedStatusPath == entry.path ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            Button(appLanguage.localized(.ui.localizationOpen.file)) {
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
            Button(appLanguage.localized(.ui.reveal.inFinder)) {
                store.revealInFinder(entry.path)
            }
            Button(appLanguage.localized(.ui.copy.fullPath)) {
                store.copyPath(entry.path)
            }
            if entry.item != .unversioned && entry.item != .ignored && entry.item != .added {
                Button(appLanguage.localized(.ui.file.commitHistoryFileCommitHistory)) {
                    Task { await store.loadFileHistory(for: entry.path) }
                }
            }
            if isVersionedFile(entry) {
                Divider()
                if lockInfo(for: entry)?.owner != store.selectedProject?.username {
                    Button(
                        lockInfo(for: entry) == nil
                            ? appLanguage.localized(.ui.lock.fileExplicitly)
                            : appLanguage.localized(.ui.review.forceLock)
                    ) {
                        Task { await store.prepareExplicitLock(paths: [lockPath(for: entry)]) }
                    }
                }
                Button(appLanguage.localized(.ui.rename.withHistory)) {
                    store.requestVersionedFileAction(.move, path: entry.path)
                }
                Button(appLanguage.localized(.ui.copy.withHistory)) {
                    store.requestVersionedFileAction(.copy, path: entry.path)
                }
                if store.recoveryState.needsLockPaths.contains(entry.path) {
                    Button(appLanguage.localized(.ui.needs.lockDisable)) {
                        Task { _ = await store.setNeedsLock(false, paths: [entry.path]) }
                    }
                } else {
                    Button(appLanguage.localized(.ui.needs.lockEnable)) {
                        Task { _ = await store.setNeedsLock(true, paths: [entry.path]) }
                    }
                }
            }
            Divider()
            if entry.item == .conflicted || entry.propertyState == .conflicted {
                Button(appLanguage.localized(.ui.resolve.conflictAction)) {
                    Task { await store.prepareConflictResolution(for: entry.path) }
                }
                Divider()
            }
            if entry.item == .unversioned {
                Button(appLanguage.localized(.ui.ignore.thisItem)) {
                    Task { await store.ignore(path: entry.path, byExtension: false) }
                }
                if !(entry.path as NSString).pathExtension.isEmpty {
                    Button(appLanguage.localized(.ui.ignore.thisExtension)) {
                        Task { await store.ignore(path: entry.path, byExtension: true) }
                    }
                }
            }
            if entry.canScheduleRepositoryDeletion {
                Divider()
                Button(appLanguage.localized(.ui.restore.localFile)) {
                    store.requestRevert(entry)
                }
                Button(appLanguage.localized(.ui.delete.fromRepository), role: .destructive) {
                    store.requestDeletion(entry)
                }
            }
            if entry.item != .unversioned
                && entry.item != .ignored
                && entry.item != .missing
                && WorkingCopyStatusPolicy.allowsRevert(entry) {
                Divider()
                Button(
                    entry.item == .conflicted || entry.propertyState == .conflicted
                        ? appLanguage.localized(.ui.revert.conflictDiscardsLocalChangesAndConflict)
                        : entry.item == .deleted
                        ? appLanguage.localized(.ui.cancel.deletionAndRestore)
                        : appLanguage.localized(.ui.revert.localChangesAction),
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
                label: appLanguage.localized(.ui.unicode.pathConflict),
                color: .orange
            )
            Text(collision.displayPath).lineLimit(1)
            Spacer()
            Text(appLanguage.localized(.ui.affected.label, collision.affectedEntryCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            if collision.id == store.pathCollisions.first?.id {
                if store.canRepairCanonicalAliases {
                    Button {
                        Task { await store.repairCanonicalAliases() }
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized(.ui.clean.upEquivalentPath),
                            isInProgress: store.isRecoveringSelectedProject
                        )
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                } else {
                    Text(appLanguage.localized(.ui.resolve.duplicateServerPathsManually))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized(.ui.multiple.canonicallyEquivalentServerPathsExi))
                }
            }
        }
    }

    private var changesToolbar: some View {
        HStack {
            Toggle(appLanguage.localized(.ui.show.ignoredFiles), isOn: Binding(
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
                        title: appLanguage.localized(.ui.delete.missingItems, missingEntries.count),
                        systemImage: "trash",
                        isInProgress: store.isDeletingSelectedProject
                    )
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
            let restorableDeletionPaths = ProjectStore.commitDeletionRestorePaths(
                requestedPaths: store.selectedPaths,
                statuses: store.visibleStatuses
            )
            if !restorableDeletionPaths.isEmpty {
                Button {
                    store.requestSelectedDeletionRestore()
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(
                            .ui.restore.selectedPendingDeletions,
                            restorableDeletionPaths.count
                        ),
                        systemImage: "arrow.uturn.backward",
                        isInProgress: store.isRevertingSelectedProject
                    )
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
            let selectedVersionedFiles = store.visibleStatuses
                .filter { store.selectedPaths.contains($0.path) && isVersionedFile($0) }
                .map(lockPath)
            if !selectedVersionedFiles.isEmpty {
                Button(appLanguage.localized(
                    .ui.lock.selectedFiles,
                    selectedVersionedFiles.count
                )) {
                    Task { await store.prepareExplicitLock(paths: selectedVersionedFiles) }
                }
                .disabled(store.isSelectedProjectActionBlocked)
                Menu {
                    Button(appLanguage.localized(.ui.needs.lockEnable)) {
                        Task { _ = await store.setNeedsLock(true, paths: selectedVersionedFiles) }
                    }
                    Button(appLanguage.localized(.ui.needs.lockDisable)) {
                        Task { _ = await store.setNeedsLock(false, paths: selectedVersionedFiles) }
                    }
                } label: {
                    Label(appLanguage.localized(.ui.needs.lockEnable), systemImage: "lock.square")
                }
                .disabled(store.isWorking)
            }
            Spacer()
            if let repositoryURL = store.recoveryState.repositoryURL {
                Text(repositoryURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(repositoryURL)
                Button(appLanguage.localized(.ui.change.repositoryLocation)) {
                    Task { await store.requestRepositoryRelocation() }
                }
                .disabled(store.isWorking)
            }
            Button(appLanguage.localized(.ui.manage.ignoreRules), systemImage: "eye.slash") {
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
        HStack(spacing: 4) {
            if entry.item != .unknown("normal") {
                StatusBadge(label: statusLabel(entry), color: statusColor(entry))
            }
            switch entry.propertyState {
            case .none:
                EmptyView()
            case .modified:
                StatusBadge(
                    label: appLanguage.localized(.ui.property.modified),
                    color: .orange
                )
            case .conflicted:
                StatusBadge(
                    label: appLanguage.localized(.ui.property.conflict),
                    color: .red
                )
            }
        }
    }

    private func statusLabel(_ entry: SVNStatusEntry) -> String {
        if TemporaryFilePolicy.isTemporaryFile(entry) {
            return appLanguage.localized(.ui.temporary.label)
        }
        return switch entry.item {
        case .modified: appLanguage.localized(.ui.modified.labelPrimary)
        case .added: appLanguage.localized(.ui.added.label)
        case .deleted: appLanguage.localized(.ui.pending.deletionPrimary)
        case .missing where entry.isMissingScheduledAddition: appLanguage.localized(.ui.cleanup.needed)
        case .missing: appLanguage.localized(.ui.pending.deletionPrimary)
        case .unversioned: appLanguage.localized(.ui.unversioned.label)
        case .ignored: appLanguage.localized(.ui.ignored.label)
        case .conflicted: appLanguage.localized(.ui.conflict.label)
        case .replaced: appLanguage.localized(.ui.replaced.label)
        case .obstructed: appLanguage.localized(.ui.obstructed.localFile)
        case .incomplete: appLanguage.localized(.ui.incomplete.updateRequired)
        case let .unknown(value): value
        }
    }

    private func statusColor(_ entry: SVNStatusEntry) -> Color {
        if TemporaryFilePolicy.isTemporaryFile(entry) { return .gray }
        if entry.isMissingScheduledAddition { return .gray }
        return WorkingCopyStatusPolicy.tone(for: entry.item).color
    }

    private var versionedFilePaths: [String] {
        store.visibleStatuses.filter(isVersionedFile).map(\.path)
    }

    private func isVersionedFile(_ entry: SVNStatusEntry) -> Bool {
        entry.nodeKind == .file
            && entry.item != .unversioned
            && entry.item != .ignored
            && entry.item != .missing
            && entry.item != .deleted
            && entry.item != .obstructed
            && entry.item != .incomplete
    }

    private func lockInfo(for entry: SVNStatusEntry) -> SVNLockInfo? {
        let repositoryPath = lockPath(for: entry)
        return store.repositoryLocks.first {
            Data($0.path.utf8) == Data(repositoryPath.utf8)
        }
    }

    private func lockPath(for entry: SVNStatusEntry) -> String {
        store.workingCopyBrowserTreeState.node(at: entry.path)?.repositoryRelativePath
            ?? entry.path
    }

    private func lockDescription(_ lock: SVNLockInfo) -> String {
        if lock.owner == store.selectedProject?.username {
            return appLanguage.localized(.ui.locked.byYou)
        }
        return appLanguage.localized(.ui.locked.by, lock.owner)
    }
}
