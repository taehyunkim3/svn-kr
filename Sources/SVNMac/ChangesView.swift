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
                if store.showsCommitProgressLog {
                    Divider()
                    commitProgressLog
                }
                Divider()
                CommitControlsView()
            }
        } detail: {
            DiffTextView(store.diffContent.localizedText(appLanguage))
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
                if entry.item == .unversioned && entry.nodeKind == .directory {
                    ForEach(store.visibleUntrackedDescendants(in: entry.path)) { row in
                        untrackedChildRow(row)
                    }
                }
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
                    appLanguage.localized(.ui.changes.noChanges),
                    systemImage: "checkmark.circle",
                    description: Text(appLanguage.localized(.ui.changes.thereNoLocallyModifiedFiles))
                )
            }
        }
    }

    private var commitProgressLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if store.isCommittingSelectedProject {
                    ProgressView().controlSize(.small)
                }
                Text(store.isCommittingSelectedProject
                    ? appLanguage.localized(.ui.commit.committing)
                    : appLanguage.localized(.ui.commit.progressLog))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(store.commitLog.isEmpty
                        ? appLanguage.localized(.ui.commit.outputAppearsHereAfterCommitStarts)
                        : store.commitLog)
                        .foregroundStyle(store.commitLog.isEmpty ? .secondary : .primary)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("commit-log-bottom")
                }
                .onChange(of: store.commitLog) { _, _ in
                    proxy.scrollTo("commit-log-bottom", anchor: .bottom)
                }
            }
            .frame(height: AppLayout.commitLogHeight)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func changedFileRow(_ entry: SVNStatusEntry) -> some View {
        HStack {
            untrackedDirectoryDisclosure(path: entry.path, isDirectory: isUntrackedDirectory(entry))
            if entry.isSelectableForCommit || entry.canScheduleRepositoryDeletion {
                Toggle("", isOn: Binding(
                    get: { store.selectedPaths.contains(entry.path) },
                    set: { checked in
                        if isUntrackedDirectory(entry) {
                            store.setUntrackedDirectorySelected(entry.path, selected: checked)
                        } else if checked {
                            store.selectedPaths.insert(entry.path)
                        } else {
                            store.selectedPaths.remove(entry.path)
                        }
                    }
                ))
                .labelsHidden()
                .disabled(store.isCommitInteractionLocked)
                .accessibilityLabel(appLanguage.localized(.ui.changes.includeCommit, entry.path))
                .help(appLanguage.localized(.ui.changes.includeExcludeFileNextCommit))
            } else {
                Image(systemName: "eye.slash").frame(width: 18)
            }
            statusBadge(entry)
            if WorkingCopyStatusPolicy.showsSwitchedWarning(entry) {
                StatusBadge(
                    label: appLanguage.localized(.ui.changes.switchedPath),
                    color: WorkingCopyStatusTone.purple.color,
                    style: .tinted
                )
                .help(appLanguage.localized(.ui.changes.pathPointsDifferentRepositoryLocationVerifyCommitDestination))
            }
            if store.recoveryState.needsLockPaths.contains(entry.path) {
                Image(systemName: "lock.square")
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized(.ui.lock.requiredBeforeEditing))
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
                        Text(appLanguage.localized(.ui.changes.filesInsideFolderAddedTogether))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let error = store.untrackedChildrenErrorsByDirectory[entry.path] {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    if WorkingCopyStatusPolicy.showsObstructionGuidance(entry) {
                        Text(appLanguage.localized(.ui.changes.unversionedLocalFileBlockingServerFileSameNameMoveRename))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if WorkingCopyStatusPolicy.showsIncompleteRecovery(entry) {
                        Text(appLanguage.localized(.ui.update.checkoutUpdateInterruptedDoNotRevertLocalChangesContinueUpdating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(appLanguage.localized(.ui.changes.showsDiffFile))
            Spacer()
            if store.loadingUntrackedDirectoryPaths.contains(entry.path) {
                ProgressView().controlSize(.small)
            }
            if entry.item == .obstructed {
                Button(appLanguage.localized(.ui.common.revealFinder)) {
                    store.revealInFinder(entry.path)
                }
            } else if WorkingCopyStatusPolicy.showsIncompleteRecovery(entry) {
                Button(appLanguage.localized(.ui.update.continueUpdating)) {
                    Task { await store.update() }
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
        }
        .listRowBackground(store.selectedStatusPath == entry.path ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            changedFileContextMenu(entry)
        }
    }

    private func untrackedChildRow(_ row: VisibleUntrackedChild) -> some View {
        let child = row.child
        let entry = SVNStatusEntry(
            path: child.path,
            item: child.isIgnored ? .ignored : .unversioned,
            nodeKind: child.isDirectory ? .directory : .file
        )
        return HStack {
            untrackedDirectoryDisclosure(path: child.path, isDirectory: child.isDirectory)
            Toggle("", isOn: Binding(
                get: {
                    store.selectedUntrackedChildPaths.contains(child.path)
                        || store.isUntrackedChildSelectionDisabled(in: row.parentDirectory)
                },
                set: { selected in
                    if child.isDirectory {
                        store.setUntrackedDirectorySelected(child.path, selected: selected)
                    } else {
                        store.setUntrackedChildSelected(
                            child.path,
                            parentDirectory: row.parentDirectory,
                            selected: selected
                        )
                    }
                }
            ))
            .labelsHidden()
            .disabled(store.isCommitInteractionLocked ||
                store.isUntrackedChildSelectionDisabled(in: row.parentDirectory))
            .accessibilityLabel(appLanguage.localized(.ui.changes.includeCommit, child.path))
            .help(appLanguage.localized(.ui.changes.includeExcludeFileNextCommit))
            statusBadge(entry)
            Button {
                Task { await store.loadDiff(for: child.path) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.path.precomposedStringWithCanonicalMapping).lineLimit(1)
                    if let error = store.untrackedChildrenErrorsByDirectory[child.path] {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(appLanguage.localized(.ui.changes.showsDiffFile))
            Spacer()
            if store.loadingUntrackedDirectoryPaths.contains(child.path) {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.leading, CGFloat(row.depth) * AppLayout.untrackedChildIndentation)
        .listRowBackground(store.selectedStatusPath == child.path ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            changedFileContextMenu(entry)
        }
    }

    @ViewBuilder
    private func untrackedDirectoryDisclosure(path: String, isDirectory: Bool) -> some View {
        if isDirectory {
            Button {
                Task {
                    await store.setUntrackedDirectoryExpanded(
                        path,
                        expanded: !store.expandedUntrackedDirectoryPaths.contains(path)
                    )
                }
            } label: {
                Image(systemName: store.expandedUntrackedDirectoryPaths.contains(path)
                    ? "chevron.down"
                    : "chevron.right")
                    .frame(
                        width: AppLayout.changesDisclosureSize.width,
                        height: AppLayout.changesDisclosureSize.height
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appLanguage.localized(
                store.expandedUntrackedDirectoryPaths.contains(path)
                    ? .ui.changes.collapseFolder
                    : .ui.changes.expandFolder,
                path
            ))
        } else {
            Color.clear
                .frame(
                    width: AppLayout.changesDisclosureSize.width,
                    height: AppLayout.changesDisclosureSize.height
                )
        }
    }

    @ViewBuilder
    private func changedFileContextMenu(_ entry: SVNStatusEntry) -> some View {
            let lockActionAvailability = FileLockActionAvailability.resolve(
                path: entry.path,
                needsLockPaths: store.recoveryState.needsLockPaths,
                loadedNeedsLockPaths: store.recoveryState.loadedNeedsLockPaths
            )
            Button(appLanguage.localized(.ui.common.openFile)) {
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
            Button(appLanguage.localized(.ui.common.revealFinder)) {
                store.revealInFinder(entry.path)
            }
            Button(appLanguage.localized(.ui.common.copyFullPath)) {
                store.copyPath(entry.path)
            }
            if entry.item != .unversioned && entry.item != .ignored && entry.item != .added {
                Button(appLanguage.localized(.ui.history.fileCommitHistory)) {
                    Task { await store.loadFileHistory(for: entry.path) }
                }
            }
            if isVersionedFile(entry) {
                Divider()
                if lockInfo(for: entry)?.owner != store.selectedProject?.username {
                    Button(
                        lockInfo(for: entry) == nil
                            ? appLanguage.localized(.ui.lock.file)
                            : appLanguage.localized(.ui.lock.reviewForceLock)
                    ) {
                        Task { await store.prepareExplicitLock(paths: [lockPath(for: entry)]) }
                    }
                    .disabled(store.isSelectedProjectActionBlocked || !lockActionAvailability.isEnabled)
                    .help(lockActionAvailability.helpMessage(
                        language: appLanguage,
                        fallback: lockInfo(for: entry) == nil
                            ? appLanguage.localized(.ui.lock.file)
                            : appLanguage.localized(.ui.lock.reviewForceLock)
                    ))
                }
                Button(appLanguage.localized(.ui.history.renameHistory)) {
                    store.requestVersionedFileAction(.move, path: entry.path)
                }
                Button(appLanguage.localized(.ui.history.copyHistory)) {
                    store.requestVersionedFileAction(.copy, path: entry.path)
                }
                if store.recoveryState.needsLockPaths.contains(entry.path) {
                    Button(appLanguage.localized(.ui.lock.removeRequiredLock)) {
                        Task { _ = await store.setNeedsLock(false, paths: [entry.path]) }
                    }
                } else {
                    Button(appLanguage.localized(.ui.lock.requireLockBeforeEditing)) {
                        Task { _ = await store.setNeedsLock(true, paths: [entry.path]) }
                    }
                }
            }
            Divider()
            if entry.item == .conflicted || entry.propertyState == .conflicted {
                Button(appLanguage.localized(.ui.conflict.openResolutionAction)) {
                    Task { await store.prepareConflictResolution(for: entry.path) }
                }
                Divider()
            }
            if entry.item == .unversioned {
                Button(appLanguage.localized(.ui.ignore.item)) {
                    Task { await store.ignore(path: entry.path, byExtension: false) }
                }
                if !(entry.path as NSString).pathExtension.isEmpty {
                    Button(appLanguage.localized(.ui.ignore.fileExtension)) {
                        Task { await store.ignore(path: entry.path, byExtension: true) }
                    }
                }
            }
            if entry.canScheduleRepositoryDeletion {
                Divider()
                Button(appLanguage.localized(.ui.changes.restoreLocalFile)) {
                    store.requestRevert(entry)
                }
                Button(appLanguage.localized(.ui.changes.deleteRepository), role: .destructive) {
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
                        ? appLanguage.localized(.ui.changes.revertConflictLocalChanges)
                        : entry.item == .deleted
                        ? appLanguage.localized(.ui.changes.cancelDeletionRestore)
                        : appLanguage.localized(.ui.commit.revertLocalChangesAction),
                    role: .destructive
                ) {
                    store.requestRevert(entry)
                }
            }
    }

    private func isUntrackedDirectory(_ entry: SVNStatusEntry) -> Bool {
        entry.item == .unversioned && entry.nodeKind == .directory
    }

    private func collisionRow(_ collision: SVNPathCollision) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)
            StatusBadge(
                label: appLanguage.localized(.ui.changes.unicodePathConflict),
                color: .orange
            )
            Text(collision.displayPath).lineLimit(1)
            Spacer()
            Text(appLanguage.localized(.ui.changes.affected, collision.affectedEntryCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            if collision.id == store.pathCollisions.first?.id {
                if store.canRepairCanonicalAliases {
                    Button {
                        Task { await store.repairCanonicalAliases() }
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized(.ui.cleanup.cleanUpEquivalentPath),
                            isInProgress: store.isRecoveringSelectedProject
                        )
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                } else {
                    Text(appLanguage.localized(.ui.changes.resolveDuplicateServerPathsManually))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(appLanguage.localized(.ui.changes.multipleCanonicallyEquivalentServerPathsExistSoAppCannotChoose))
                }
            }
        }
    }

    private var changesToolbar: some View {
        HStack {
            Toggle(appLanguage.localized(.ui.changes.showIgnoredFiles), isOn: Binding(
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
                        title: appLanguage.localized(.ui.changes.deletePendingItems, missingEntries.count),
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
                            .ui.changes.restorePendingDeletions,
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
                    .ui.lock.selectedFile,
                    selectedVersionedFiles.count
                )) {
                    Task { await store.prepareExplicitLock(paths: selectedVersionedFiles) }
                }
                .disabled(store.isSelectedProjectActionBlocked)
                Menu {
                    Button(appLanguage.localized(.ui.lock.requireLockBeforeEditing)) {
                        Task { _ = await store.setNeedsLock(true, paths: selectedVersionedFiles) }
                    }
                    Button(appLanguage.localized(.ui.lock.removeRequiredLock)) {
                        Task { _ = await store.setNeedsLock(false, paths: selectedVersionedFiles) }
                    }
                } label: {
                    Label(appLanguage.localized(.ui.lock.requireLockBeforeEditing), systemImage: "lock.square")
                }
                .disabled(store.isSelectedProjectActionBlocked)
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
            }
            Button(appLanguage.localized(.ui.ignore.manageIgnoreRules), systemImage: "eye.slash") {
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
                    label: appLanguage.localized(.ui.changes.propertiesModified),
                    color: .orange
                )
            case .conflicted:
                StatusBadge(
                    label: appLanguage.localized(.ui.conflict.propertyConflict),
                    color: .red
                )
            }
        }
    }

    private func statusLabel(_ entry: SVNStatusEntry) -> String {
        if TemporaryFilePolicy.isTemporaryFile(entry) {
            return appLanguage.localized(.ui.changes.temporary)
        }
        return switch entry.item {
        case .modified: appLanguage.localized(.ui.status.modified)
        case .added: appLanguage.localized(.ui.status.added)
        case .deleted: appLanguage.localized(.ui.changes.pendingDeletionStatus)
        case .missing where entry.isMissingScheduledAddition: appLanguage.localized(.ui.cleanup.needed)
        case .missing: appLanguage.localized(.ui.changes.pendingDeletionStatus)
        case .unversioned: appLanguage.localized(.ui.status.unversioned)
        case .ignored: appLanguage.localized(.ui.status.ignored)
        case .conflicted: appLanguage.localized(.ui.conflict.conflict)
        case .replaced: appLanguage.localized(.ui.status.replaced)
        case .obstructed: appLanguage.localized(.ui.update.localFileBlockingUpdate)
        case .incomplete: appLanguage.localized(.ui.update.incomplete)
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
        return ChangesLockMatcher.lockInfo(for: repositoryPath, in: store.repositoryLocks)
    }

    private func lockPath(for entry: SVNStatusEntry) -> String {
        store.workingCopyBrowserTreeState.node(at: entry.path)?.repositoryRelativePath
            ?? entry.path
    }

    private func lockDescription(_ lock: SVNLockInfo) -> String {
        if lock.owner == store.selectedProject?.username {
            return appLanguage.localized(.ui.lock.lockedByCurrentUser)
        }
        return appLanguage.localized(.ui.lock.lockedByOwner, lock.owner)
    }
}

enum ChangesLockMatcher {
    static func lockInfo(for path: String, in locks: [SVNLockInfo]) -> SVNLockInfo? {
        let lockPaths = locks.map(\.path)
        return locks.first {
            CanonicalPathMatcher.matches(path, candidate: $0.path, among: lockPaths)
        }
    }
}
