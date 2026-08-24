import SwiftUI
import SVNCore

struct RepositoryPathNormalizationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider()
            guidance
            Divider()
            selectionBar
            Divider()
            targetList
            Divider()
            commitMessage
            Divider()
            footer
        }
        .appSheetFrame(minimumSize: AppLayout.repositoryPathNormalizationSheetMinimumSize)
        .sheet(isPresented: $store.isConfirmingRepositoryPathNormalization) {
            RepositoryPathNormalizationConfirmationView()
                .environment(store)
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
        .interactiveDismissDisabled(store.isRepositoryPathNormalizationRunning)
    }

    private var header: some View {
        HStack {
            Label(
                appLanguage.localized("repository.path.normalization.title"),
                systemImage: "character.book.closed"
            )
            .font(.title2.bold())
            Spacer()
            Button(appLanguage.localized("ui.close.3ea43db3"), role: .cancel) {
                store.isShowingRepositoryPathNormalization = false
            }
            .keyboardShortcut(.cancelAction)
            .disabled(store.isRepositoryPathNormalizationRunning)
        }
        .padding()
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                appLanguage.localized("repository.path.normalization.same.appearance.note"),
                systemImage: "info.circle"
            )
            Label(
                appLanguage.localized("repository.path.normalization.directory.note"),
                systemImage: "folder.badge.gearshape"
            )
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var selectionBar: some View {
        HStack {
            Text(
                appLanguage.localized(
                    "ui.selected.685ae833",
                    store.selectedRepositoryPathNormalizationTargets.count
                )
            )
            .foregroundStyle(.secondary)
            Spacer()
            Button(
                store.allRepositoryPathNormalizationTargetsAreSelected
                    ? appLanguage.localized("repository.path.normalization.deselect.all")
                    : appLanguage.localized("ui.select.all.ef1f5eca")
            ) {
                store.setAllRepositoryPathNormalizationTargetsSelected(
                    !store.allRepositoryPathNormalizationTargetsAreSelected
                )
            }
            .disabled(
                store.repositoryPathNormalizationTargets.isEmpty
                    || store.isRepositoryPathNormalizationRunning
                    || store.repositoryPathNormalizationResult != nil
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var targetList: some View {
        List {
            if let issue = store.repositoryPathNormalizationIssue {
                issueSection(issue)
            }
            if let result = store.repositoryPathNormalizationResult {
                resultSections(result)
            }
            if !store.repositoryPathNormalizationTargets.isEmpty {
                Section(appLanguage.localized("repository.path.normalization.targets")) {
                    ForEach(store.repositoryPathNormalizationTargets) { target in
                        targetRow(target)
                    }
                }
            }
        }
        .overlay {
            if store.isScanningRepositoryPaths {
                ProgressView(
                    appLanguage.localized("repository.path.normalization.scanning.detail")
                )
            } else if store.repositoryPathNormalizationTargets.isEmpty,
                      store.repositoryPathNormalizationIssue == nil {
                ContentUnavailableView(
                    appLanguage.localized("repository.path.normalization.waiting"),
                    systemImage: "character.book.closed"
                )
            }
        }
    }

    private func targetRow(_ target: SVNRepositoryPathNormalizationTarget) -> some View {
        Toggle(
            isOn: Binding(
                get: {
                    store.selectedRepositoryPathNormalizationTargets.contains(target)
                },
                set: { _ in store.toggleRepositoryPathNormalizationTarget(target) }
            )
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    target.isDirectory
                        ? appLanguage.localized("ui.folder.e6474408")
                        : appLanguage.localized("ui.file.811b7680"),
                    systemImage: target.isDirectory ? "folder.fill" : "doc.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    pathRow(
                        appLanguage.localized("repository.path.normalization.before"),
                        path: target.repositoryPath
                    )
                    pathRow(
                        appLanguage.localized("repository.path.normalization.after"),
                        path: target.normalizedPath
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(
            store.isRepositoryPathNormalizationRunning
                || store.repositoryPathNormalizationResult != nil
        )
    }

    private func pathRow(_ label: String, path: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(path)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }

    private func issueSection(
        _ issue: RepositoryPathNormalizationIssue
    ) -> some View {
        Section {
            ErrorDetailsText(
                message: issueDetails(issue),
                maximumHeight: AppLayout.inlineErrorMaximumHeight
            )
            HStack {
                Spacer()
                ErrorCopyButton(message: issueDetails(issue))
            }
        } header: {
            Label(
                appLanguage.localized("repository.path.normalization.problem"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
        }
    }

    private func issueDetails(_ issue: RepositoryPathNormalizationIssue) -> String {
        ([issue.localizedMessage(appLanguage)] + issue.paths.map { "• \($0)" })
            .joined(separator: "\n")
    }

    @ViewBuilder
    private func resultSections(
        _ result: SVNRepositoryPathNormalizationResult
    ) -> some View {
        Section {
            Label(
                appLanguage.localized(
                    "repository.path.normalization.result.summary",
                    result.renamedTargets.count,
                    result.committedRevisions.count
                ),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            if !result.committedRevisions.isEmpty {
                Text(
                    appLanguage.localized(
                        "repository.path.normalization.result.revisions",
                        result.committedRevisions.joined(separator: ", ")
                    )
                )
                .textSelection(.enabled)
            }
        } header: {
            Text(appLanguage.localized("repository.path.normalization.result"))
        }

        if !result.skippedTargets.isEmpty {
            Section {
                Text(appLanguage.localized("repository.path.normalization.skipped.reason"))
                    .foregroundStyle(.secondary)
                ForEach(result.skippedTargets) { target in
                    Text(target.repositoryPath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text(
                    appLanguage.localized(
                        "repository.path.normalization.skipped",
                        result.skippedTargets.count
                    )
                )
            }
        }
    }

    private var commitMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLanguage.localized("ui.commit.message.c5139167"))
                .font(.headline)
            TextField(
                appLanguage.localized("ui.commit.message.c5139167"),
                text: Binding(
                    get: { store.repositoryPathNormalizationCommitMessage },
                    set: { store.repositoryPathNormalizationCommitMessage = $0 }
                )
            )
            .disabled(
                store.isRepositoryPathNormalizationRunning
                    || store.repositoryPathNormalizationResult != nil
            )
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if store.isNormalizingRepositoryPaths {
                ProgressView(
                    appLanguage.localized("repository.path.normalization.running")
                )
                .controlSize(.small)
            }
            Spacer()
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                store.isShowingRepositoryPathNormalization = false
            }
            .disabled(store.isRepositoryPathNormalizationRunning)
            if shouldOfferRescan {
                Button(appLanguage.localized("repository.path.normalization.scan.again")) {
                    Task { await store.beginRepositoryPathNormalization() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isRepositoryPathNormalizationRunning)
            } else {
                Button(appLanguage.localized("repository.path.normalization.review.action")) {
                    store.requestRepositoryPathNormalizationConfirmation()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canConfirmRepositoryPathNormalization)
            }
        }
        .padding()
    }

    private var shouldOfferRescan: Bool {
        if store.repositoryPathNormalizationResult != nil { return true }
        guard let issue = store.repositoryPathNormalizationIssue else { return false }
        return issue.kind == .invalidTargets
            || store.repositoryPathNormalizationTargets.isEmpty
    }
}

private struct RepositoryPathNormalizationConfirmationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    private var selectedCount: Int {
        store.selectedRepositoryPathNormalizationTargets.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized("repository.path.normalization.confirmation.title"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)

            warning(
                appLanguage.localized(
                    "repository.path.normalization.confirmation.commits",
                    selectedCount
                ),
                systemImage: "shippingbox.and.arrow.backward"
            )
            warning(
                appLanguage.localized(
                    "repository.path.normalization.confirmation.delete.add"
                ),
                systemImage: "arrow.left.arrow.right"
            )
            warning(
                appLanguage.localized(
                    "repository.path.normalization.confirmation.directory"
                ),
                systemImage: "folder.badge.gearshape"
            )
            warning(
                appLanguage.localized(
                    "repository.path.normalization.confirmation.team"
                ),
                systemImage: "person.3"
            )

            GroupBox(appLanguage.localized("ui.commit.message.c5139167")) {
                Text(store.repositoryPathNormalizationCommitMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }

            Spacer()

            HStack {
                Spacer()
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                    store.isConfirmingRepositoryPathNormalization = false
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    Task { await store.normalizeSelectedRepositoryPaths() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(
                            "repository.path.normalization.confirmation.run",
                            selectedCount
                        ),
                        inProgressTitle: appLanguage.localized(
                            "repository.path.normalization.running"
                        ),
                        systemImage: "checkmark",
                        isInProgress: store.isNormalizingRepositoryPaths
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canConfirmRepositoryPathNormalization)
            }
        }
        .padding()
        .appSheetFrame(
            minimumSize: AppLayout.repositoryPathNormalizationConfirmationSheetMinimumSize
        )
        .interactiveDismissDisabled(store.isNormalizingRepositoryPaths)
    }

    private func warning(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
