import SwiftUI
import SVNCore

/// 현재 작업 복사본 범위에서 서버가 보고한 잠금과 소유자를 표시합니다.
struct RepositoryLocksView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.localized(.ui.repository.locks)).font(.title2.bold())
                Spacer()
                Button {
                    Task { await store.loadRepositoryLocks() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.refresh.label),
                        isInProgress: store.isLoadingSelectedProjectLocks
                    )
                }
                .disabled(store.isLoadingSelectedProjectLocks)
                if !store.ownedRepositoryLocks.isEmpty {
                    Button(appLanguage.localized(
                        .ui.release.allMyLocks,
                        store.ownedRepositoryLocks.count
                    )) {
                        store.requestBulkUnlock()
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                }
                Button(appLanguage.localized(.ui.close.label)) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            Label {
                Text(appLanguage.localized(.ui.a.lockedFileIsMarkedOnTheSvnServerToPre))
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
                            title: appLanguage.localized(.ui.release.lockNormally),
                            isInProgress: store.isLoadingSelectedProjectLocks
                        )
                    }
                    .disabled(store.isSelectedProjectActionBlocked)
                    .help(appLanguage.localized(.ui.localizationTry.normalUnlockBeforeForceUnlock))
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.repositoryLocks.isEmpty, store.isLoadingSelectedProjectLocks {
                    ProgressView(appLanguage.localized(.ui.loading.repositoryLocks))
                } else if store.repositoryLocks.isEmpty {
                    ContentUnavailableView(appLanguage.localized(.ui.no.lockedFiles), systemImage: "lock.open")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.repositoryLocksSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
        .alert(
            appLanguage.localized(.ui.force.releaseRepositoryLock),
            isPresented: .isPresenting($store.forceUnlockRequest),
            presenting: store.forceUnlockRequest
        ) { request in
            Button(appLanguage.localized(.ui.force.releaseLock), role: .destructive) {
                Task { await store.forceUnlock(request) }
            }
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                store.forceUnlockRequest = nil
            }
        } message: { request in
            Text(forceUnlockDetails(request))
        }
        .alert(
            appLanguage.localized(.ui.bulk.unlockConfirmationTitle),
            isPresented: .isPresenting($store.recoveryState.bulkUnlockRequest),
            presenting: store.recoveryState.bulkUnlockRequest
        ) { request in
            Button(appLanguage.localized(.ui.release.locksCount, request.locks.count)) {
                Task { await store.confirmBulkUnlock(request) }
            }
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                store.recoveryState.bulkUnlockRequest = nil
            }
        } message: { request in
            Text(appLanguage.localized(
                .ui.bulk.unlockConfirmationDetails,
                request.locks.count
            ))
        }
        .alert(
            appLanguage.localized(.ui.bulk.unlockPartialFailureTitle),
            isPresented: .isPresenting($store.recoveryState.bulkUnlockResult),
            presenting: store.recoveryState.bulkUnlockResult
        ) { _ in
            Button(appLanguage.localized(.ui.close.label)) {
                store.recoveryState.bulkUnlockResult = nil
            }
        } message: { result in
            Text(bulkUnlockResultDetails(result))
        }
    }

    private func forceUnlockDetails(_ request: ForceUnlockRequest) -> String {
        let lock = request.lock
        let created = lock.created?.formatted(date: .numeric, time: .standard)
            ?? appLanguage.localized(.ui.not.available)
        let comment = lock.comment.flatMap { $0.isEmpty ? nil : $0 }
            ?? appLanguage.localized(.ui.not.available)
        return appLanguage.localized(
            .ui.force.unlockDetailsOwnerTimeCommentOriginal,
            lock.path,
            lock.owner,
            created,
            comment,
            request.originalMessage
        )
    }

    private func bulkUnlockResultDetails(_ result: BulkUnlockResult) -> String {
        let failures = result.failures
            .map { "\($0.path)\n\($0.message)" }
            .joined(separator: "\n\n")
        return appLanguage.localized(
            .ui.bulk.unlockPartialFailureDetails,
            result.releasedPaths.count,
            result.requestedCount,
            failures
        )
    }
}
