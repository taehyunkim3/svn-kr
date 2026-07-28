import SwiftUI

private struct RevertConfirmationModifier: ViewModifier {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        content.alert(
            appLanguage.text("로컬 변경을 되돌릴까요?", "Revert Local Changes?"),
            isPresented: Binding(get: { store.revertRequest != nil }, set: { if !$0 { store.revertRequest = nil } }),
            presenting: store.revertRequest
        ) { request in
            Button(appLanguage.text("되돌리기", "Revert"), role: .destructive) { Task { await store.confirmRevert(request) } }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) { store.revertRequest = nil }
        } message: { request in
            if request.entry.item == .missing || request.entry.item == .deleted {
                Text(appLanguage.text(
                    "\(request.entry.path)의 저장소 삭제 표시를 취소하고 저장소 기준 파일을 로컬에 복원합니다.",
                    "Cancel the repository deletion state for \(request.entry.path) and restore the repository version locally."
                ))
            } else {
                Text(appLanguage.text(
                    "\(request.entry.path)의 커밋하지 않은 변경이 삭제됩니다. 이 작업은 SVN으로 복구할 수 없습니다.",
                    "Uncommitted changes in \(request.entry.path) will be discarded and cannot be restored by SVN."
                ))
            }
        }
    }
}

extension View {
    func revertConfirmation() -> some View { modifier(RevertConfirmationModifier()) }
}
