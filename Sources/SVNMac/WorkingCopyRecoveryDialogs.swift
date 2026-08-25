import SwiftUI

struct WorkingCopyCleanupView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    let request: WorkingCopyCleanupRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized("ui.working.copy.cleanup.62f3ac11"),
                systemImage: "wrench.and.screwdriver"
            )
            .font(.title2.bold())

            Text(appLanguage.localized("ui.operation.was.interrupted.cleanup.prompt.c7f01d92"))
            Text(request.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !request.originalMessage.isEmpty {
                ErrorDetailsText(message: request.originalMessage)
            }

            HStack {
                Spacer()
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                    store.dismissWorkingCopyCleanupRequest()
                    dismiss()
                }
                .disabled(store.isCleaningSelectedWorkingCopy)
                Button {
                    Task {
                        if await store.cleanupSelectedWorkingCopy() {
                            dismiss()
                        }
                    }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.run.working.copy.cleanup.b71c28de"),
                        inProgressTitle: appLanguage.localized("ui.cleaning.working.copy.2a9ed647"),
                        isInProgress: store.isCleaningSelectedWorkingCopy
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.isCleaningSelectedWorkingCopy)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.errorDetailsSheetMinimumSize)
        .interactiveDismissDisabled(store.isCleaningSelectedWorkingCopy)
    }
}

struct CanceledCheckoutRecoveryView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    let request: CanceledCheckoutRecoveryRequest
    @State private var isConfirmingEmptyFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized("ui.checkout.was.interrupted.9d8a23c0"),
                systemImage: "arrow.clockwise"
            )
            .font(.title2.bold())

            Text(appLanguage.localized("ui.incomplete.checkout.recovery.options.f31ea907"))
            Text(request.destinationPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                if request.canEmptySafely {
                    Button(appLanguage.localized("ui.empty.checkout.folder.7a1c8e53"), role: .destructive) {
                        isConfirmingEmptyFolder = true
                    }
                    .disabled(store.isRecoveringCanceledCheckout)
                } else {
                    Label(
                        appLanguage.localized("ui.checkout.folder.was.not.empty.cannot.delete.0e6d49b2"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3"), role: .cancel) {
                    store.dismissCanceledCheckoutRecovery(request)
                    dismiss()
                }
                .disabled(store.isRecoveringCanceledCheckout)
                Button {
                    Task { _ = await store.resumeCanceledCheckout(request) }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.continue.checkout.84b37ce1"),
                        inProgressTitle: appLanguage.localized("ui.cleaning.and.continuing.checkout.18fa2d6b"),
                        isInProgress: store.isRecoveringCanceledCheckout
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.isRecoveringCanceledCheckout)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.errorDetailsSheetMinimumSize)
        .interactiveDismissDisabled(store.isRecoveringCanceledCheckout)
        .alert(
            appLanguage.localized("ui.empty.canceled.checkout.folder.confirmation.6e12c9ad"),
            isPresented: $isConfirmingEmptyFolder
        ) {
            Button(appLanguage.localized("ui.empty.folder.destructive.30d295e8"), role: .destructive) {
                Task { await store.emptyCanceledCheckout(request) }
            }
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {}
        } message: {
            Text(appLanguage.localized(
                "ui.only.verified.working.copy.will.be.deleted.path.d8c0a71e",
                request.destinationPath
            ))
        }
    }
}
