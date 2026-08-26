import SwiftUI

extension View {
    func explicitLockConfirmation() -> some View {
        modifier(ExplicitLockConfirmationModifier())
    }
}

private struct ExplicitLockConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(
            appLanguage.localized(.ui.lock.takeAnotherUserLock),
            isPresented: .isPresenting($store.recoveryState.explicitLockRequest),
            presenting: store.recoveryState.explicitLockRequest
        ) { request in
            Button(appLanguage.localized(.ui.lock.forceLock), role: .destructive) {
                Task { await store.forceExplicitLock(request) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.recoveryState.explicitLockRequest = nil
            }
        } message: { request in
            Text(appLanguage.localized(
                .ui.lock.forceLockingSelectedFileRemovesExistingUsersLocksReviewOwners,
                request.paths.count,
                request.conflictingLocks.map { "\($0.path) — \($0.owner)" }.joined(separator: "\n")
            ))
        }
    }
}
