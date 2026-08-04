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
                Text(appLanguage.localized("ui.repository.locks.dff91f03")).font(.title2.bold())
                Spacer()
                Button {
                    Task { await store.loadRepositoryLocks() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.refresh.0aca6bd2"),
                        isInProgress: store.isLoadingSelectedProjectLocks
                    )
                }
                .disabled(store.isLoadingSelectedProjectLocks)
                Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            Label {
                Text(appLanguage.localized("ui.a.locked.file.is.marked.on.the.svn.server.to.pre.d248a309"))
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
                    if lock.owner == store.selectedProject?.username {
                        Button {
                            Task { await store.unlock(lock) }
                        } label: {
                            ActionProgressLabel(
                                title: appLanguage.localized("ui.release.my.lock.1b0c3150"),
                                isInProgress: store.isLoadingSelectedProjectLocks
                            )
                        }
                        .disabled(store.isSelectedProjectActionBlocked)
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.repositoryLocks.isEmpty, store.isLoadingSelectedProjectLocks {
                    ProgressView(appLanguage.localized("ui.loading.repository.locks.3dd2dfdb"))
                } else if store.repositoryLocks.isEmpty {
                    ContentUnavailableView(appLanguage.localized("ui.no.locked.files.7d32eee0"), systemImage: "lock.open")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.repositoryLocksSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }
}
