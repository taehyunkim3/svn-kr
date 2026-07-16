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

            if store.repositoryLocks.isEmpty {
                ContentUnavailableView(appLanguage.text("잠긴 파일 없음", "No Locked Files"), systemImage: "lock.open")
            } else {
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
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }
}
