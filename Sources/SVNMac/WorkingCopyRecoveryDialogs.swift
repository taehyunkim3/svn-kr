import SwiftUI

struct WorkingCopyCleanupView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    let request: WorkingCopyCleanupRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized(.ui.cleanup.workingCopyCleanup),
                systemImage: "wrench.and.screwdriver"
            )
            .font(.title2.bold())

            Text(appLanguage.localized(.ui.cleanup.operationInterruptedLikeCleanUpWorkingCopyTryAgainCleanup))
            Text(request.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !request.originalMessage.isEmpty {
                ErrorDetailsText(message: request.originalMessage)
            }

            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
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
                        title: appLanguage.localized(.ui.cleanup.runCleanup),
                        inProgressTitle: appLanguage.localized(.ui.cleanup.cleaningWorkingCopy),
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
                appLanguage.localized(.ui.recovery.checkoutInterrupted),
                systemImage: "arrow.clockwise"
            )
            .font(.title2.bold())

            Text(appLanguage.localized(.ui.recovery.folderIncompleteSvnWorkingCopyContinueRegisteringItCleaningIt))
            Text(request.destinationPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                if request.canEmptySafely {
                    Button(appLanguage.localized(.ui.recovery.emptyFolderRequestAction), role: .destructive) {
                        isConfirmingEmptyFolder = true
                    }
                    .disabled(store.isRecoveringCanceledCheckout)
                } else {
                    Label(
                        appLanguage.localized(.ui.recovery.folderAlreadyFilesBeforeCheckoutSoAppNotEmptyIt),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(appLanguage.localized(.ui.common.close), role: .cancel) {
                    store.dismissCanceledCheckoutRecovery(request)
                    dismiss()
                }
                .disabled(store.isRecoveringCanceledCheckout)
                Button {
                    Task { _ = await store.resumeCanceledCheckout(request) }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.recovery.continueCheckout),
                        inProgressTitle: appLanguage.localized(.ui.recovery.cleaningContinuing),
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
            appLanguage.localized(.ui.recovery.emptyInterruptedCheckoutFolder),
            isPresented: $isConfirmingEmptyFolder
        ) {
            Button(appLanguage.localized(.ui.recovery.emptyFolderConfirmationAction), role: .destructive) {
                Task { await store.emptyCanceledCheckout(request) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {}
        } message: {
            Text(appLanguage.localized(
                .ui.recovery.allContentsVerifiedInterruptedSvnWorkingCopyFolderBelowDeleted,
                request.destinationPath
            ))
        }
    }
}
