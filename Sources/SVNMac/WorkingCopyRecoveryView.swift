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
                    appLanguage.localized(.ui.recovery.automaticUnicodePathRecovery),
                    systemImage: "cross.case"
                )
                .font(.headline)
                Spacer()
                Button(appLanguage.localized(.ui.common.close)) {
                    store.isShowingPathRecovery = false
                }
                .disabled(store.isPathRecoveryRunning)
            }

            Text(appLanguage.localized(.ui.recovery.cleanWorkingCopyCheckedOutServerOnlyRealLocalChanges))
            .foregroundStyle(.secondary)

            if let preview = store.pathRecoveryPreview {
                GroupBox(appLanguage.localized(.ui.recovery.preview)) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        previewRow(appLanguage.localized(.ui.status.modified), value: preview.modifiedCount)
                        previewRow(appLanguage.localized(.ui.recovery.new), value: preview.addedCount)
                        previewRow(appLanguage.localized(.ui.recovery.locallyMissing), value: preview.deletedCount)
                        previewRow(appLanguage.localized(.ui.recovery.falseAliasesExcluded), value: preview.ignoredAliasCount)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !preview.blockingPaths.isEmpty {
                    Label(
                        appLanguage.localized(
                            .recovery.path.reviewPaths,
                            preview.blockingPaths.joined(separator: ", ")
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            GroupBox(appLanguage.localized(.ui.recovery.newWorkingFolder)) {
                HStack {
                    Text(destinationURL?.path ?? appLanguage.localized(.ui.recovery.chooseEmptyFolder))
                        .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button(appLanguage.localized(.ui.recovery.chooseFolder), systemImage: "folder") {
                        chooseDestination()
                    }
                    .disabled(store.isPathRecoveryRunning)
                }
                .padding(.vertical, 4)
            }

            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appLanguage.localized(.ui.error.error), systemImage: "exclamationmark.triangle.fill")
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
                Text(appLanguage.localized(.ui.recovery.successBothOriginalRecoveredCopiesRemainSidebar))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if store.isPathRecoveryRunning { ProgressView().controlSize(.small) }
                Button(appLanguage.localized(.ui.recovery.recoverNewWorkingFolder)) {
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
        panel.title = appLanguage.localized(.ui.recovery.chooseEmptyRecoveryFolder)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destinationURL = panel.url?.standardizedFileURL }
    }
}
