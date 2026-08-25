import SwiftUI
import SVNCore

struct CommitConfirmationRequest: Identifiable {
    let id: UUID
    let projectID: SVNProject.ID
    let message: String
    let selectedPaths: Set<String>
    let serverDeletionEntries: [SVNStatusEntry]

    init(
        id: UUID = UUID(),
        projectID: SVNProject.ID,
        message: String,
        selectedPaths: Set<String>,
        statuses: [SVNStatusEntry]
    ) {
        self.id = id
        self.projectID = projectID
        self.message = message
        self.selectedPaths = selectedPaths
        serverDeletionEntries = statuses
            .filter { entry in
                selectedPaths.contains(entry.path)
                    && (entry.item == .deleted || entry.canScheduleRepositoryDeletion)
            }
            .sorted { $0.path < $1.path }
    }
}

struct CommitConfirmationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: CommitConfirmationRequest

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            Text(appLanguage.localized("ui.review.commit.8b36485e"))
                .font(.title2.bold())

            if !serverDeletionEntries.isEmpty {
                Text(appLanguage.localized("ui.server.deletion.warning.81e94f35"))

                Label(
                    appLanguage.localized(
                        "ui.server.deletion.count.793b7522",
                        serverDeletionEntries.count
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(.orange)
            }

            List(serverDeletionEntries, selection: $store.selectedCommitDeletionRestorePaths) { entry in
                HStack {
                    Image(systemName: entry.nodeKind == .directory ? "folder" : "doc")
                    Text(entry.path.precomposedStringWithCanonicalMapping)
                        .font(.body.monospaced())
                }
            }
            .overlay {
                if serverDeletionEntries.isEmpty {
                    ContentUnavailableView(
                        appLanguage.localized("ui.no.server.deletions.remaining.3e7b9a12"),
                        systemImage: "checkmark.circle"
                    )
                }
            }

            HStack {
                Button(appLanguage.localized("ui.restore.selected.server.files.4f2a7c91")) {
                    store.requestCommitDeletionRestore()
                }
                .disabled(
                    store.selectedCommitDeletionRestorePaths.isEmpty
                        || store.isSelectedProjectActionBlocked
                )
                Spacer()
                Text(appLanguage.localized(
                    "ui.selected.685ae833",
                    store.selectedCommitDeletionRestorePaths.count
                ))
                .foregroundStyle(.secondary)
            }

            if let failureMessage = store.commitDeletionRestoreFailureMessage {
                Text(failureMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if request.message.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage.localized("ui.commit.without.a.message.6f0f2d41"))
                        .font(.headline)
                    Text(appLanguage.localized("ui.the.commit.will.be.recorded.with.an.empty.messag.9c31be05"))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button(appLanguage.localized("ui.no.bafd7322"), role: .cancel) {
                    store.cancelCommitConfirmation()
                }
                .keyboardShortcut(.cancelAction)
                Button(appLanguage.localized("ui.confirm.commit.7c2e5a90")) {
                    guard let currentRequest = store.commitConfirmationRequest else { return }
                    Task { _ = await store.confirmCommit(currentRequest) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.isSelectedProjectActionBlocked)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.commitConfirmationSheetMinimumSize)
        .interactiveDismissDisabled(
            store.isCommittingSelectedProject
                || store.isDeletingSelectedProject
                || store.isRevertingSelectedProject
        )
        .alert(
            appLanguage.localized("ui.restore.selected.files.confirmation.6d81b3e4"),
            isPresented: .isPresenting($store.commitDeletionRestoreRequest),
            presenting: store.commitDeletionRestoreRequest
        ) { restoreRequest in
            Button(appLanguage.localized("ui.restore.selected.files.action.7b3e1d95")) {
                Task { await store.confirmCommitDeletionRestore(restoreRequest) }
            }
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                store.cancelCommitDeletionRestore()
            }
        } message: { restoreRequest in
            Text(appLanguage.localized(
                "ui.restore.selected.files.count.2c9f4a70",
                restoreRequest.paths.count
            ))
        }
    }

    private var serverDeletionEntries: [SVNStatusEntry] {
        store.commitConfirmationRequest?.serverDeletionEntries ?? request.serverDeletionEntries
    }
}
