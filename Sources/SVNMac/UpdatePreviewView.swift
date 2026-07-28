import SwiftUI
import SVNCore

/// 작업 복사본을 변경하기 전에 서버에서 내려올 경로를 확인시키는 안전 장치입니다.
struct UpdatePreviewView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.text("업데이트 미리보기", "Update Preview")).font(.title2.bold())
                Spacer()
                Button(appLanguage.text("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List(store.remoteChanges) { entry in
                HStack {
                    remoteBadge(entry.item)
                    Text(entry.path).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            .overlay {
                if store.remoteChanges.isEmpty, store.isPreviewingSelectedProjectUpdate {
                    ProgressView(appLanguage.text("서버 변경 확인 중…", "Checking incoming changes…"))
                } else if store.remoteChanges.isEmpty {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: store.isWorkingCopyOutOfDate == true ? "arrow.down.circle" : "checkmark.circle",
                        description: Text(emptyStateDescription)
                    )
                }
            }

            Divider()
            HStack {
                Text(appLanguage.text("업데이트 중 로컬 변경과 겹치면 SVN 충돌이 발생할 수 있습니다.", "Incoming changes that overlap local edits may create an SVN conflict."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.remoteChanges.isEmpty || store.isWorkingCopyOutOfDate == true {
                    Button(appLanguage.text("업데이트 실행", "Run Update")) { Task { await store.update() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isUpdatingSelectedProject)
                }
            }
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.updatePreviewSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var emptyStateTitle: String {
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.text("업데이트 필요", "Update Required")
        }
        return appLanguage.text("내려받을 변경 없음", "No Incoming Changes")
    }

    private var emptyStateDescription: String {
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.text(
                "삭제 예정 경로의 서버 변경은 목록에 표시되지 않을 수 있습니다. 업데이트를 실행한 뒤 충돌 상태를 확인하세요.",
                "Server changes inside a pending deletion may not appear in this list. Run Update, then review any conflicts."
            )
        }
        return appLanguage.text(
            "현재 로컬 작업 폴더가 서버와 최신 상태입니다.",
            "The working copy is up to date with the server."
        )
    }

    private func remoteBadge(_ item: SVNStatusKind) -> some View {
        StatusBadge(
            label: item.rawValue.uppercased(),
            color: item == .deleted ? .red : .blue
        )
    }
}
