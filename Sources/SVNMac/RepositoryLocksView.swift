import SwiftUI
import SVNCore

/// 현재 작업 복사본 범위에서 서버가 보고한 잠금과 소유자를 표시합니다.
struct RepositoryLocksView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.text("저장소 파일 잠금", "Repository Locks")).font(.title2.bold())
                Spacer()
                Button(appLanguage.text("새로고침", "Refresh")) { Task { await store.loadRepositoryLocks() } }
                Button(appLanguage.text("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            Label {
                Text(appLanguage.text(
                    "잠금 파일은 편집 중인 파일에 다른 사용자가 동시에 커밋하지 못하도록 SVN 서버에 표시한 파일입니다. 내가 잠근 파일은 커밋에 성공하면 자동으로 잠금이 해제됩니다.",
                    "A locked file is marked on the SVN server to prevent another user from committing to it while it is being edited. Your lock is released automatically after a successful commit."
                ))
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
                        Button(appLanguage.text("내 잠금 해제", "Release My Lock")) {
                            Task { await store.unlock(lock) }
                        }
                        .disabled(store.isWorking)
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.repositoryLocks.isEmpty {
                    ContentUnavailableView(appLanguage.text("잠긴 파일 없음", "No Locked Files"), systemImage: "lock.open")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.repositoryLocksSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }
}
