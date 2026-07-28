import SwiftUI

private struct RevertConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(
            appLanguage.localized("ui.revert.local.changes.0fa51499"),
            isPresented: .isPresenting($store.revertRequest),
            presenting: store.revertRequest
        ) { request in
            Button(appLanguage.localized("ui.revert.f621e9ba"), role: .destructive) { Task { await store.confirmRevert(request) } }
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) { store.revertRequest = nil }
        } message: { request in
            if request.entry.item == .missing || request.entry.item == .deleted {
                Text(appLanguage.localized("ui.cancel.the.repository.deletion.state.for.and.res.fe2dce5e", request.entry.path))
            } else {
                Text(appLanguage.localized("ui.uncommitted.changes.in.will.be.discarded.and.can.df7e8671", request.entry.path))
            }
        }
    }
}

extension View {
    func revertConfirmation() -> some View { modifier(RevertConfirmationModifier()) }
}
