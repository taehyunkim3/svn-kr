import SwiftUI
import SVNCore

enum BulkUnlockResultPresentation {
    static func failureList(_ result: BulkUnlockResult) -> String {
        result.failures.map(\.path).joined(separator: "\n")
    }
}

/// 현재 작업 복사본 범위에서 서버가 보고한 잠금과 소유자를 표시합니다.
struct RepositoryLocksView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.localized(.ui.lock.repositoryLocks)).font(.title2.bold())
                Spacer()
                Button {
                    Task { await store.loadRepositoryLocks() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.common.refresh),
                        isInProgress: store.isLoadingSelectedProjectLocks
                    )
                }
                .disabled(store.isLoadingSelectedProjectLocks)
                if !store.ownedRepositoryLocks.isEmpty {
                    Button(appLanguage.localized(
                        .ui.lock.releaseAllAction,
                        store.ownedRepositoryLocks.count
                    )) {
                        store.requestBulkUnlock()
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                }
                Button(appLanguage.localized(.ui.common.close)) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            Label {
                Text(appLanguage.localized(.ui.lock.lockedFileMarkedSvnServerPreventAnotherUserCommittingIt))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 10)
            Divider()

            List(store.repositoryLocks) { lock in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lock.path).font(.body.monospaced())
                        Label(lock.owner, systemImage: "person")
                            .iconHelp(appLanguage.localized(.ui.lock.lockedByOwner, lock.owner))
                        if let comment = lock.comment, !comment.isEmpty {
                            Text(comment).foregroundStyle(.secondary)
                        }
                        if let created = lock.created {
                            Text(created.formatted(date: .numeric, time: .standard)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    Spacer()
                    Button {
                        Task { await store.unlock(lock) }
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized(.ui.lock.releaseFromListAction),
                            isInProgress: store.isLoadingSelectedProjectLocks
                        )
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                    .help(appLanguage.localized(.ui.lock.tryNormalUnlockFirstIfWorkingCopyNoMatchingLock))
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.repositoryLocks.isEmpty, store.isLoadingSelectedProjectLocks {
                    ProgressView(appLanguage.localized(.ui.lock.loadingRepositoryLocks))
                } else if store.repositoryLocks.isEmpty {
                    ContentUnavailableView(appLanguage.localized(.ui.lock.noLockedFiles), systemImage: "lock.open")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.repositoryLocksSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
        .alert(
            appLanguage.localized(.ui.lock.forceReleaseRepositoryLock),
            isPresented: .isPresenting($store.forceUnlockRequest),
            presenting: store.forceUnlockRequest
        ) { request in
            Button(appLanguage.localized(.ui.lock.forceReleaseLock), role: .destructive) {
                Task { await store.forceUnlock(request) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.forceUnlockRequest = nil
            }
        } message: { request in
            Text(forceUnlockDetails(request))
        }
        .alert(
            appLanguage.localized(.ui.lock.releaseAllConfirmationTitle),
            isPresented: .isPresenting($store.recoveryState.bulkUnlockRequest),
            presenting: store.recoveryState.bulkUnlockRequest
        ) { request in
            Button(appLanguage.localized(.ui.lock.releaseLocks, request.locks.count)) {
                Task { await store.confirmBulkUnlock(request) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.recoveryState.bulkUnlockRequest = nil
            }
        } message: { request in
            Text(appLanguage.localized(
                .ui.lock.releaseLocksOwnedCurrentUserOtherUsersAbleModifyFiles,
                request.locks.count
            ))
        }
        .alert(
            appLanguage.localized(.ui.lock.someLocksNotReleased),
            isPresented: .isPresenting($store.recoveryState.bulkUnlockResult),
            presenting: store.recoveryState.bulkUnlockResult
        ) { _ in
            Button(appLanguage.localized(.ui.common.close)) {
                store.recoveryState.bulkUnlockResult = nil
            }
        } message: { result in
            Text(bulkUnlockResultDetails(result))
        }
    }

    private func forceUnlockDetails(_ request: ForceUnlockRequest) -> String {
        let lock = request.lock
        let created = lock.created?.formatted(date: .numeric, time: .standard)
            ?? appLanguage.localized(.ui.lock.notAvailable)
        let comment = lock.comment.flatMap { $0.isEmpty ? nil : $0 }
            ?? appLanguage.localized(.ui.lock.notAvailable)
        return appLanguage.localized(
            .ui.lock.forceReleasingCanInterruptSomeoneElseWorkPathOwnerLocked,
            lock.path,
            lock.owner,
            created,
            comment,
            request.originalMessage
        )
    }

    private func bulkUnlockResultDetails(_ result: BulkUnlockResult) -> String {
        return appLanguage.localized(
            .ui.lock.releasedLocksLocksBelowCouldNotReleased,
            result.releasedPaths.count,
            result.requestedCount,
            BulkUnlockResultPresentation.failureList(result)
        )
    }
}
