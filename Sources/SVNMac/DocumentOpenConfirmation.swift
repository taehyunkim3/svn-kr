import SwiftUI

/// 문서 계열 파일을 열기 전에 저장소 잠금의 의미를 설명하고 사용자의 선택을 받습니다.
private struct DocumentOpenConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.confirmationDialog(
            appLanguage.localized("ui.lock.this.file.before.opening.0d16b072"),
            isPresented: .isPresenting($store.documentOpenRequest),
            titleVisibility: .visible,
            presenting: store.documentOpenRequest
        ) { request in
            if request.existingLock == nil {
                Button(appLanguage.localized("ui.lock.and.open.c64beb29")) {
                    Task { await store.lockAndOpen(request) }
                }
            }
            Button(appLanguage.localized("ui.open.without.lock.e650efbf")) {
                store.openWithoutLock(request)
            }
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                store.documentOpenRequest = nil
            }
        } message: { request in
            if let lock = request.existingLock {
                Text(appLanguage.localized("ui.this.file.is.currently.locked.by.opening.without.ca1f8e9a", lock.owner))
            } else {
                Text(appLanguage.localized("ui.locking.prevents.concurrent.commits.by.other.use.0f657e2c"))
            }
        }
    }
}

extension View {
    func documentOpenConfirmation() -> some View {
        modifier(DocumentOpenConfirmationModifier())
    }
}
