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
            appLanguage.localized(.ui.force.lockConfirmationTitle),
            isPresented: .isPresenting($store.recoveryState.explicitLockRequest),
            presenting: store.recoveryState.explicitLockRequest
        ) { request in
            Button(appLanguage.localized(.ui.force.lockConfirmationAction), role: .destructive) {
                Task { await store.forceExplicitLock(request) }
            }
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                store.recoveryState.explicitLockRequest = nil
            }
        } message: { request in
            Text(appLanguage.localized(
                .ui.force.lockConfirmationDetails,
                request.paths.count,
                request.conflictingLocks.map { "\($0.path) — \($0.owner)" }.joined(separator: "\n")
            ))
        }
    }
}
