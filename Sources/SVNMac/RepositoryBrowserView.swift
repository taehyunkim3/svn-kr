import AppKit
import SVNCore
import SwiftUI

struct RepositoryBrowserView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var state: RepositoryBrowserState

    @MainActor
    init(
        repositoryListing: any SVNClientServing,
        repositoryURL: String,
        revision: String? = nil,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) {
        _state = State(initialValue: RepositoryBrowserState(
            repositoryListing: repositoryListing,
            repositoryURL: repositoryURL,
            revision: revision,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ))
    }

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            header
            Divider()
            browseInputs
            Divider()
            currentLocation
            Divider()
            repositoryList(selection: $state.selectedEntryID)
            Divider()
            footer
        }
        .appSheetFrame(minimumSize: AppLayout.repositoryLocksSheetMinimumSize)
        .task {
            guard state.phase == .idle,
                  !state.repositoryURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            await state.browse()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.localized("ui.browse.svn.repository.4a9d3c10"))
                    .font(.title2.bold())
                Text(appLanguage.localized("ui.browse.repository.before.checkout.7c2e1b84"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var browseInputs: some View {
        @Bindable var state = state
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text(appLanguage.localized("ui.repository.url.a29f5816"))
                TextField("https://server/svn/project/trunk", text: $state.repositoryURLInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: AppLayout.repositoryURLFieldMinimumWidth)
                Button {
                    Task { await state.browse() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.browse.5f8b6e21"),
                        inProgressTitle: appLanguage.localized("ui.loading.b0a3fd42"),
                        isInProgress: state.isLoading
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    state.repositoryURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || state.isLoading
                )
            }
            GridRow {
                Text(appLanguage.localized("ui.revision.optional.63ad9f02"))
                TextField("HEAD", text: $state.revisionInput)
                    .textFieldStyle(.roundedBorder)
                EmptyView()
            }
        }
        .padding()
    }

    private var currentLocation: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.navigateUp() }
            } label: {
                Label(
                    appLanguage.localized("ui.parent.directory.1b7e4a93"),
                    systemImage: "arrow.up"
                )
            }
            .disabled(!state.canNavigateUp || state.isLoading)

            VStack(alignment: .leading, spacing: 3) {
                Text(appLanguage.localized("ui.current.repository.url.1a6f43d2"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.currentURL.isEmpty ? state.repositoryURLInput : state.currentURL)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                copyCurrentURL()
            } label: {
                Label(
                    appLanguage.localized("ui.copy.current.repository.url.82c5d1f0"),
                    systemImage: "doc.on.doc"
                )
            }
            .disabled(state.currentURL.isEmpty)
        }
        .padding()
    }

    private func repositoryList(
        selection: Binding<SVNRepositoryEntry.ID?>
    ) -> some View {
        List(state.entries, selection: selection) { entry in
            repositoryRow(entry)
                .tag(entry.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard entry.kind == .directory else { return }
                    state.selectedEntryID = entry.id
                    Task { await state.enterSelectedDirectory() }
                }
        }
        .overlay { repositoryListOverlay }
    }

    private func repositoryRow(_ entry: SVNRepositoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind == .directory ? "folder.fill" : "doc")
                .foregroundStyle(entry.kind == .directory ? .blue : .secondary)
                .accessibilityLabel(appLanguage.localized(
                    entry.kind == .directory
                        ? "ui.directory.9e3f2a70"
                        : "ui.file.6d4b8c21"
                ))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                HStack(spacing: 10) {
                    Text("r\(entry.lastChangedRevision)")
                    if let author = entry.lastChangedAuthor, !author.isEmpty {
                        Label(author, systemImage: "person")
                    }
                    if let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if let date = entry.lastChangedDate {
                        Text(date.formatted(date: .numeric, time: .shortened))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var repositoryListOverlay: some View {
        switch state.phase {
        case .idle:
            ContentUnavailableView(
                appLanguage.localized("ui.enter.repository.url.to.browse.3f6a9d20"),
                systemImage: "externaldrive.connected.to.line.below"
            )
        case .loading:
            ProgressView(appLanguage.localized("ui.loading.repository.contents.5e1c7a84"))
        case .loaded where state.entries.isEmpty:
            ContentUnavailableView(
                appLanguage.localized("ui.repository.directory.empty.7a2c5e90"),
                systemImage: "folder",
                description: Text(appLanguage.localized("ui.no.items.in.repository.directory.4d8b1f63"))
            )
        case .failed(let failure):
            ContentUnavailableView {
                Label(failureTitle(failure.kind), systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.details).textSelection(.enabled)
            }
        case .loaded:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await state.refresh() }
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized("ui.refresh.0aca6bd2"),
                    isInProgress: state.isLoading
                )
            }
            .disabled(state.currentURL.isEmpty || state.isLoading)
            Spacer()
            Button(appLanguage.localized("ui.open.selected.directory.2c7e5a91")) {
                Task { await state.enterSelectedDirectory() }
            }
            .disabled(state.selectedEntry?.kind != .directory || state.isLoading)
            Button(appLanguage.localized("ui.use.repository.path.8f1d4b62")) {
                store.recoveryState.repositoryBrowseSelectedURL = state.checkoutURL
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.checkoutURL == nil || state.isLoading)
        }
        .padding()
    }

    private func failureTitle(_ kind: RepositoryBrowserFailure.Kind) -> String {
        switch kind {
        case .authentication:
            appLanguage.localized("ui.repository.authentication.failed.6b2e9c14")
        case .invalidURL:
            appLanguage.localized("ui.invalid.repository.url.8e4c1a70")
        case .connection:
            appLanguage.localized("ui.repository.connection.failed.1e5a7c93")
        case .other:
            appLanguage.localized("ui.repository.contents.failed.3c8f2d61")
        }
    }

    private func copyCurrentURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(state.currentURL, forType: .string)
    }
}
