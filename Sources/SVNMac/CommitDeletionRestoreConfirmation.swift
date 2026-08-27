import SwiftUI

enum CommitDeletionRestorePresentationOwner {
    case changes
    case commitConfirmation

    func ownsPresentation(hasCommitConfirmation: Bool) -> Bool {
        switch self {
        case .changes:
            !hasCommitConfirmation
        case .commitConfirmation:
            hasCommitConfirmation
        }
    }
}

private struct CommitDeletionRestorePresentationOwnerKey: EnvironmentKey {
    static let defaultValue = CommitDeletionRestorePresentationOwner.changes
}

extension EnvironmentValues {
    var commitDeletionRestorePresentationOwner: CommitDeletionRestorePresentationOwner {
        get { self[CommitDeletionRestorePresentationOwnerKey.self] }
        set { self[CommitDeletionRestorePresentationOwnerKey.self] = newValue }
    }
}

/// 삭제 예정 항목을 서버 파일로 복원하기 전에 확인을 받는 공통 알림입니다.
/// 변경 사항 목록과 커밋 확인 화면이 같은 문구와 동작을 사용하도록 한곳에 둡니다.
private struct CommitDeletionRestoreConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.commitDeletionRestorePresentationOwner) private var presentationOwner

    func body(content: Content) -> some View {
        @Bindable var store = store
        let ownsPresentation = presentationOwner.ownsPresentation(
            hasCommitConfirmation: store.commitConfirmationRequest != nil
        )
        content.alert(
            appLanguage.localized(.ui.commit.restoreSelectedFilesConfirmationTitle),
            isPresented: Binding(
                get: { ownsPresentation && store.commitDeletionRestoreRequest != nil },
                set: { isPresented in
                    if ownsPresentation, !isPresented {
                        store.cancelCommitDeletionRestore()
                    }
                }
            ),
            presenting: ownsPresentation ? store.commitDeletionRestoreRequest : nil
        ) { restoreRequest in
            Button(appLanguage.localized(.ui.commit.restoreServer)) {
                Task { await store.confirmCommitDeletionRestore(restoreRequest) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.cancelCommitDeletionRestore()
            }
            .confirmationKeyboardShortcut(for: .cancel, behavior: .commitDeletionRestore)
        } message: { restoreRequest in
            Text(appLanguage.localized(
                .ui.commit.restoreSelectedDeletionFileServer,
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
