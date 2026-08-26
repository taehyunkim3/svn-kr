import SwiftUI

private struct RevertConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(
            appLanguage.localized(.ui.commit.revertLocalChangesConfirmationTitle),
            isPresented: .isPresenting($store.revertRequest),
            presenting: store.revertRequest
        ) { request in
            Button(appLanguage.localized(.ui.commit.revert), role: .destructive) { Task { await store.confirmRevert(request) } }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) { store.revertRequest = nil }
        } message: { request in
            if request.entry.item == .missing || request.entry.item == .deleted {
                Text(appLanguage.localized(.ui.commit.cancelRepositoryDeletionStateRestoreRepositoryVersionLocally, request.entry.path))
            } else {
                Text(appLanguage.localized(.ui.commit.uncommittedChangesDiscardedCannotRestoredSvn, request.entry.path))
            }
        }
    }
}

extension View {
    func revertConfirmation() -> some View { modifier(RevertConfirmationModifier()) }
}
