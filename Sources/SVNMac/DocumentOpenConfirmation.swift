import SwiftUI

/// 문서 계열 파일을 열기 전에 저장소 잠금의 의미를 설명하고 사용자의 선택을 받습니다.
private struct DocumentOpenConfirmationModifier: ViewModifier {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        content.confirmationDialog(
            appLanguage.text("먼저 파일을 잠그고 여시겠습니까?", "Lock This File Before Opening?"),
            isPresented: Binding(
                get: { store.documentOpenRequest != nil },
                set: { if !$0 { store.documentOpenRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: store.documentOpenRequest
        ) { request in
            if request.existingLock == nil {
                Button(appLanguage.text("잠그고 열기", "Lock and Open")) {
                    Task { await store.lockAndOpen(request) }
                }
            }
            Button(appLanguage.text("잠그지 않고 열기", "Open Without Lock")) {
                store.openWithoutLock(request)
            }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) {
                store.documentOpenRequest = nil
            }
        } message: { request in
            if let lock = request.existingLock {
                Text(appLanguage.text(
                    "현재 \(lock.owner) 사용자가 잠근 파일입니다. 잠그지 않고 열면 변경 내용을 커밋할 수 없거나 충돌할 수 있습니다.",
                    "This file is currently locked by \(lock.owner). Opening without a lock may prevent committing or cause a conflict."
                ))
            } else {
                Text(appLanguage.text(
                    "잠그면 다른 사용자의 동시 커밋을 방지해 문서 충돌을 줄일 수 있습니다. 커밋에 성공하면 잠금은 자동으로 해제됩니다.",
                    "Locking prevents concurrent commits by other users and reduces document conflicts. A successful commit automatically releases the lock."
                ))
            }
        }
    }
}

extension View {
    func documentOpenConfirmation() -> some View {
        modifier(DocumentOpenConfirmationModifier())
    }
}
