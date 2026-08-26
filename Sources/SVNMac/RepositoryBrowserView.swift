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
        .onDisappear { state.cancelLoading() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appLanguage.localized(.ui.browser.browseSvnRepository))
                    .font(.title2.bold())
                Text(appLanguage.localized(.ui.browser.checkFoldersFilesBeforeChoosingRepositoryPathCheckOut))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(appLanguage.localized(.ui.common.close)) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var browseInputs: some View {
        @Bindable var state = state
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text(appLanguage.localized(.ui.browser.repositoryUrl))
                TextField("https://server/svn/project/trunk", text: $state.repositoryURLInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: AppLayout.repositoryURLFieldMinimumWidth)
                Button {
                    state.beginBrowse()
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.browser.browse),
                        inProgressTitle: appLanguage.localized(.ui.history.loading),
                        isInProgress: state.isLoading
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    state.repositoryURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            GridRow {
                Text(appLanguage.localized(.ui.browser.revisionOptional))
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
                state.beginNavigateUp()
            } label: {
                Label(
                    appLanguage.localized(.ui.browser.parentDirectory),
                    systemImage: "arrow.up"
                )
            }
            .disabled(!state.canNavigateUp)

            VStack(alignment: .leading, spacing: 3) {
                Text(appLanguage.localized(.ui.repository.currentRepositoryUrl))
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
                    appLanguage.localized(.ui.repository.copyCurrentRepositoryUrl),
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
                    state.beginEnterSelectedDirectory()
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
                        ? .ui.browser.directory
                        : .ui.browser.fileAccessibilityLabel
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
                appLanguage.localized(.ui.browser.enterRepositoryUrlBrowse),
                systemImage: "externaldrive.connected.to.line.below"
            )
        case .loading:
            ProgressView(appLanguage.localized(.ui.browser.loadingRepositoryContents))
        case .loaded where state.entries.isEmpty:
            ContentUnavailableView(
                appLanguage.localized(.ui.browser.directoryEmpty),
                systemImage: "folder",
                description: Text(appLanguage.localized(.ui.browser.repositoryReturnedNoFilesSubdirectoriesPath))
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
                state.beginRefresh()
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized(.ui.common.refresh),
                    isInProgress: state.isLoading
                )
            }
            .disabled(state.currentURL.isEmpty)
            Spacer()
            Button(appLanguage.localized(.ui.browser.openSelectedDirectory)) {
                state.beginEnterSelectedDirectory()
            }
            .disabled(state.selectedEntry?.kind != .directory)
            Button(appLanguage.localized(.ui.browser.useRepositoryPath)) {
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
            appLanguage.localized(.ui.authentication.repositoryAuthenticationFailed)
        case .invalidURL:
            appLanguage.localized(.ui.repository.enterValidRepositoryUrlIncludingItsScheme)
        case .connection:
            appLanguage.localized(.ui.browser.couldNotConnectRepository)
        case .other:
            appLanguage.localized(.ui.browser.couldNotLoadRepositoryContents)
        }
    }

    private func copyCurrentURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(state.currentURL, forType: .string)
    }
}
