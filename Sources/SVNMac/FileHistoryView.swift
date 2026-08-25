import AppKit
import SwiftUI

struct FileHistoryView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(appLanguage.localized("ui.file.commit.history.ab024244")).font(.title2.bold())
                    if let path = store.fileHistoryPath { Text(path).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List(store.fileHistory) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("r\(entry.revision)").font(.headline.monospacedDigit())
                        Label(entry.author, systemImage: "person").font(.caption)
                        Spacer()
                        if let date = entry.date { Text(date.formatted(date: .numeric, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                    }
                    SVNLogMessageView(entry: entry)
                    HStack {
                        Button {
                            saveRevision(entry.revision)
                        } label: {
                            ActionProgressLabel(
                                title: appLanguage.localized("ui.save.this.revision.as.3e8d79a1"),
                                inProgressTitle: appLanguage.localized("ui.saving.revision.4fb2c8d0"),
                                isInProgress: store.isSavingHistoryRevision(entry.revision)
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .destructive) {
                            guard let path = store.fileHistoryPath else { return }
                            store.requestHistoryRevisionRestore(
                                revision: entry.revision,
                                relativePath: path
                            )
                        } label: {
                            ActionProgressLabel(
                                title: appLanguage.localized("ui.restore.working.file.to.revision.79c4a2e6"),
                                inProgressTitle: appLanguage.localized("ui.restoring.revision.c840d51f"),
                                isInProgress: store.isRestoringHistoryRevision(entry.revision)
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(
                        store.isSelectedProjectActionBlocked
                            || store.isHistoryRevisionOperationRunning
                    )
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.fileHistory.isEmpty, store.isLoadingSelectedFileHistory {
                    ProgressView(appLanguage.localized("ui.loading.file.history.c6c155f3"))
                } else if store.fileHistory.isEmpty {
                    ContentUnavailableView(appLanguage.localized("ui.no.file.history.c4cc1ef1"), systemImage: "clock")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.fileHistorySheetMinimumSize)
        .confirmationDialog(
            appLanguage.localized("ui.restore.working.file.confirmation.0ab7e3c9"),
            isPresented: restoreConfirmationBinding,
            titleVisibility: .visible,
            presenting: store.recoveryState.historyRevisionRestoreRequest
        ) { request in
            Button(
                appLanguage.localized("ui.restore.working.file.to.revision.79c4a2e6"),
                role: .destructive
            ) {
                Task { await store.confirmHistoryRevisionRestore(request) }
            }
            Button(appLanguage.localized("ui.cancel.89b99401"), role: .cancel) {}
        } message: { request in
            Text(
                appLanguage.localized(
                    "ui.restore.working.file.warning.62d159af",
                    request.relativePath,
                    request.revision
                )
            )
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var restoreConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.recoveryState.historyRevisionRestoreRequest != nil },
            set: { isPresented in
                if !isPresented {
                    store.recoveryState.historyRevisionRestoreRequest = nil
                }
            }
        )
    }

    private func saveRevision(_ revision: String) {
        guard let relativePath = store.fileHistoryPath else { return }
        let panel = NSSavePanel()
        panel.title = appLanguage.localized("ui.save.this.revision.as.3e8d79a1")
        panel.prompt = appLanguage.localized("ui.save.this.revision.as.3e8d79a1")
        panel.nameFieldStringValue = defaultSaveName(for: relativePath, revision: revision)
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        Task {
            await store.saveHistoryRevision(
                revision: revision,
                relativePath: relativePath,
                to: destinationURL
            )
        }
    }

    private func defaultSaveName(for relativePath: String, revision: String) -> String {
        let original = URL(fileURLWithPath: relativePath)
        let stem = original.deletingPathExtension().lastPathComponent
        guard !original.pathExtension.isEmpty else { return "\(stem)_r\(revision)" }
        return "\(stem)_r\(revision).\(original.pathExtension)"
    }
}
