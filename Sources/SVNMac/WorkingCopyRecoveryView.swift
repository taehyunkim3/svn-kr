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
                    appLanguage.localized("ui.automatic.unicode.path.recovery.e71b00a0"),
                    systemImage: "cross.case"
                )
                .font(.headline)
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3")) {
                    store.isShowingPathRecovery = false
                }
                .disabled(store.isPathRecoveryRunning)
            }

            Text(appLanguage.localized("ui.a.clean.working.copy.is.checked.out.from.the.ser.a49ce026"))
            .foregroundStyle(.secondary)

            if let preview = store.pathRecoveryPreview {
                GroupBox(appLanguage.localized("ui.recovery.preview.be45be07")) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        previewRow(appLanguage.localized("ui.modified.01365bb2"), value: preview.modifiedCount)
                        previewRow(appLanguage.localized("ui.new.479ccc40"), value: preview.addedCount)
                        previewRow(appLanguage.localized("ui.locally.missing.c4011027"), value: preview.deletedCount)
                        previewRow(appLanguage.localized("ui.false.aliases.excluded.85d448dd"), value: preview.ignoredAliasCount)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !preview.blockingPaths.isEmpty {
                    Label(
                        appLanguage.localized(
                            "recovery.review.paths",
                            preview.blockingPaths.joined(separator: ", ")
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            GroupBox(appLanguage.localized("ui.new.working.folder.5db27c9c")) {
                HStack {
                    Text(destinationURL?.path ?? appLanguage.localized("ui.choose.an.empty.folder.8f9acb6e"))
                        .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button(appLanguage.localized("ui.choose.folder.54647179"), systemImage: "folder") {
                        chooseDestination()
                    }
                    .disabled(store.isPathRecoveryRunning)
                }
                .padding(.vertical, 4)
            }

            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(appLanguage.localized("ui.error.a08d7e0d"), systemImage: "exclamationmark.triangle.fill")
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
                Text(appLanguage.localized("ui.on.success.both.the.original.and.recovered.copie.9a6ba4b9"))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if store.isPathRecoveryRunning { ProgressView().controlSize(.small) }
                Button(appLanguage.localized("ui.recover.to.new.working.folder.141e043c")) {
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
        panel.title = appLanguage.localized("ui.choose.an.empty.recovery.folder.c2b4a175")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destinationURL = panel.url?.standardizedFileURL }
    }
}
