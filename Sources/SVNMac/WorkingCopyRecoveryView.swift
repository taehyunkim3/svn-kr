import AppKit
import SwiftUI
import SVNCore

struct WorkingCopyRecoveryView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @State private var destinationURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(
                    appLanguage.localized(.ui.automatic.unicodePathRecovery),
                    systemImage: "cross.case"
                )
                .font(.headline)
                Spacer()
                Button(appLanguage.localized(.ui.close.label)) {
                    store.isShowingPathRecovery = false
                }
                .disabled(store.isPathRecoveryRunning)
            }

            Text(appLanguage.localized(.ui.a.cleanWorkingCopyIsCheckedOutFromTheSer))
            .foregroundStyle(.secondary)

            if let preview = store.pathRecoveryPreview {
                GroupBox(appLanguage.localized(.ui.recovery.preview)) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        previewRow(appLanguage.localized(.ui.modified.labelPrimary), value: preview.modifiedCount)
                        previewRow(appLanguage.localized(.ui.new.label), value: preview.addedCount)
                        previewRow(appLanguage.localized(.ui.locally.missing), value: preview.deletedCount)
                        previewRow(appLanguage.localized(.ui.localizationFalse.aliasesExcluded), value: preview.ignoredAliasCount)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !preview.blockingPaths.isEmpty {
                    Label(
                        appLanguage.localized(
                            .recovery.reviewPaths,
                            preview.blockingPaths.joined(separator: ", ")
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            GroupBox(appLanguage.localized(.ui.new.workingFolder)) {
                HStack {
                    Text(destinationURL?.path ?? appLanguage.localized(.ui.choose.anEmptyFolder))
                        .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button(appLanguage.localized(.ui.choose.folder), systemImage: "folder") {
                        chooseDestination()
                    }
                    .disabled(store.isPathRecoveryRunning)
                }
                .padding(.vertical, 4)
            }

            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appLanguage.localized(.ui.error.label), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    ErrorDetailsText(
                        message: error,
                        maximumHeight: AppLayout.inlineErrorMaximumHeight
                    )
                    HStack {
                        Spacer()
                        ErrorCopyButton(message: error)
                    }
                }
            }

            Spacer()

            HStack {
                Text(appLanguage.localized(.ui.on.successBothTheOriginalAndRecoveredCopie))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if store.isPathRecoveryRunning { ProgressView().controlSize(.small) }
                Button(appLanguage.localized(.ui.recover.toNewWorkingFolder)) {
                    Task { _ = await store.recoverWorkingCopy(to: destinationURL) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    destinationURL == nil
                        || store.pathRecoveryPreview?.blockingPaths.isEmpty != true
                        || store.isPathRecoveryRunning
                )
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.pathRecoverySheetMinimumSize)
    }

    @ViewBuilder
    private func previewRow(_ label: String, value: Int) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value.formatted()).monospacedDigit()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = appLanguage.localized(.ui.choose.anEmptyRecoveryFolder)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destinationURL = panel.url?.standardizedFileURL }
    }
}
