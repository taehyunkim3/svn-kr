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
                    Text(appLanguage.localized(.ui.revision.fileCommitHistory)).font(.title2.bold())
                    if let path = store.fileHistoryPath { Text(path).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(appLanguage.localized(.ui.common.close)) { dismiss() }.keyboardShortcut(.cancelAction)
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
                    if let fileHistoryRequest = store.fileHistoryRequest {
                        HistoryRevisionActions(
                            fileHistoryRequest: fileHistoryRequest,
                            revision: entry.revision
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.fileHistory.isEmpty, store.isLoadingSelectedFileHistory {
                    ProgressView(appLanguage.localized(.ui.revision.loadingFileHistory))
                } else if store.fileHistory.isEmpty {
                    ContentUnavailableView(appLanguage.localized(.ui.revision.noFileHistory), systemImage: "clock")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.fileHistorySheetMinimumSize)
        .historyRevisionRestoreConfirmation()
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }
}

struct HistoryRevisionActions: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    let fileHistoryRequest: FileHistoryRequest
    let revision: String

    var body: some View {
        HStack {
            Button {
                saveRevision()
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized(.ui.revision.saveRevision),
                    inProgressTitle: appLanguage.localized(.ui.revision.savingRevision),
                    isInProgress: store.isSavingHistoryRevision(revision)
                )
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                guard store.fileHistoryRequest?.id == fileHistoryRequest.id else { return }
                store.requestHistoryRevisionRestore(revision: revision)
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized(.ui.revision.restoreWorkingFileRevision),
                    inProgressTitle: appLanguage.localized(.ui.revision.restoringRevision),
                    isInProgress: store.isRestoringHistoryRevision(revision)
                )
            }
            .buttonStyle(.bordered)
        }
        .disabled(
            store.isSelectedProjectActionBlocked
                || store.isHistoryRevisionOperationRunning
        )
    }

    private func saveRevision() {
        guard store.fileHistoryRequest?.id == fileHistoryRequest.id else { return }
        let relativePath = fileHistoryRequest.relativePath
        let panel = NSSavePanel()
        panel.title = appLanguage.localized(.ui.revision.saveRevision)
        panel.prompt = appLanguage.localized(.ui.revision.saveRevision)
        panel.nameFieldStringValue = defaultSaveName(for: relativePath, revision: revision)
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        let request = HistoryRevisionSaveRequest(
            fileHistoryRequestID: fileHistoryRequest.id,
            projectID: fileHistoryRequest.projectID,
            relativePath: relativePath,
            revision: revision,
            destinationURL: destinationURL
        )
        Task {
            await store.saveHistoryRevision(request)
        }
    }

    private func defaultSaveName(for relativePath: String, revision: String) -> String {
        let original = URL(fileURLWithPath: relativePath)
        let stem = original.deletingPathExtension().lastPathComponent
        guard !original.pathExtension.isEmpty else { return "\(stem)_r\(revision)" }
        return "\(stem)_r\(revision).\(original.pathExtension)"
    }
}

private struct HistoryRevisionRestoreConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.confirmationDialog(
            appLanguage.localized(.ui.revision.restoreWorkingFile),
            isPresented: Binding(
                get: { store.recoveryState.historyRevisionRestoreRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        store.recoveryState.historyRevisionRestoreRequest = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: store.recoveryState.historyRevisionRestoreRequest
        ) { request in
            Button(
                appLanguage.localized(.ui.revision.restoreWorkingFileRevision),
                role: .destructive
            ) {
                Task { await store.confirmHistoryRevisionRestore(request) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {}
        } message: { request in
            Text(
                appLanguage.localized(
                    .ui.revision.currentContentsDiscardedReplacedRRecoveryCopySavedFirstResult,
                    request.relativePath,
                    request.revision
                )
            )
        }
    }
}

extension View {
    func historyRevisionRestoreConfirmation() -> some View {
        modifier(HistoryRevisionRestoreConfirmationModifier())
    }
}
