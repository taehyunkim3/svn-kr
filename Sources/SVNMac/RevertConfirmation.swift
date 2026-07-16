import SwiftUI

private struct RevertConfirmationModifier: ViewModifier {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        content.alert(
            appLanguage.text("로컬 변경을 되돌릴까요?", "Revert Local Changes?"),
            isPresented: Binding(get: { store.revertRequest != nil }, set: { if !$0 { store.revertRequest = nil } }),
            presenting: store.revertRequest
        ) { _ in
            Button(appLanguage.text("되돌리기", "Revert"), role: .destructive) { Task { await store.confirmRevert() } }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) { store.revertRequest = nil }
        } message: { request in
            Text(appLanguage.text(
                "\(request.entry.path)의 커밋하지 않은 변경이 삭제됩니다. 이 작업은 SVN으로 복구할 수 없습니다.",
                "Uncommitted changes in \(request.entry.path) will be discarded and cannot be restored by SVN."
            ))
        }
    }
}

extension View {
    func revertConfirmation() -> some View { modifier(RevertConfirmationModifier()) }
}
