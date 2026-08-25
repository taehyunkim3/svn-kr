import SwiftUI

/// 삭제 예정 항목을 서버 파일로 복원하기 전에 확인을 받는 공통 알림입니다.
/// 변경 사항 목록과 커밋 확인 화면이 같은 문구와 동작을 사용하도록 한곳에 둡니다.
private struct CommitDeletionRestoreConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(
            appLanguage.localized(.ui.restore.selectedFilesConfirmation),
            isPresented: .isPresenting($store.commitDeletionRestoreRequest),
            presenting: store.commitDeletionRestoreRequest
        ) { restoreRequest in
            Button(appLanguage.localized(.ui.restore.selectedFilesAction)) {
                Task { await store.confirmCommitDeletionRestore(restoreRequest) }
            }
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                store.cancelCommitDeletionRestore()
            }
        } message: { restoreRequest in
            Text(appLanguage.localized(
                .ui.restore.selectedFilesCount,
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
