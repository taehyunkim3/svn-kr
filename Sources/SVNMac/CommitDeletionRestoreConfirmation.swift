import SwiftUI

/// 삭제 예정 항목을 서버 파일로 복원하기 전에 확인을 받는 공통 알림입니다.
/// 변경 사항 목록과 커밋 확인 화면이 같은 문구와 동작을 사용하도록 한곳에 둡니다.
private struct CommitDeletionRestoreConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(
            appLanguage.localized("ui.restore.selected.files.confirmation.6d81b3e4"),
            isPresented: .isPresenting($store.commitDeletionRestoreRequest),
            presenting: store.commitDeletionRestoreRequest
        ) { restoreRequest in
            Button(appLanguage.localized("ui.restore.selected.files.action.7b3e1d95")) {
                Task { await store.confirmCommitDeletionRestore(restoreRequest) }
            }
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                store.cancelCommitDeletionRestore()
            }
        } message: { restoreRequest in
            Text(appLanguage.localized(
                "ui.restore.selected.files.count.2c9f4a70",
                restoreRequest.paths.count
            ))
        }
    }
}

extension View {
    func commitDeletionRestoreConfirmation() -> some View {
        modifier(CommitDeletionRestoreConfirmationModifier())
    }
}
