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
                appLanguage.localized(.repository.pathNormalizationTitle),
                systemImage: "character.book.closed"
            )
            .font(.title2.bold())
            Spacer()
            Button(appLanguage.localized(.ui.close.label), role: .cancel) {
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
                appLanguage.localized(.repository.pathNormalizationWindowsNote),
                systemImage: "desktopcomputer"
            )
            Label(
                appLanguage.localized(.repository.pathNormalizationSameAppearanceNote),
                systemImage: "info.circle"
            )
            Label(
                appLanguage.localized(.repository.pathNormalizationDirectoryNote),
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
                    .ui.selected.label,
                    store.selectedRepositoryPathNormalizationTargets.count
                )
            )
            .foregroundStyle(.secondary)
            Spacer()
            Button(
                store.allRepositoryPathNormalizationTargetsAreSelected
                    ? appLanguage.localized(.repository.pathNormalizationDeselectAll)
                    : appLanguage.localized(.ui.select.allSelectAll2)
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
                Section(appLanguage.localized(.repository.pathNormalizationTargets)) {
                    ForEach(store.repositoryPathNormalizationTargets) { target in
                        targetRow(target)
                    }
                }
            }
        }
        .overlay {
            if store.isScanningRepositoryPaths {
                ProgressView(
                    appLanguage.localized(.repository.pathNormalizationScanningDetail)
                )
            } else if store.repositoryPathNormalizationTargets.isEmpty,
                      store.repositoryPathNormalizationIssue == nil {
                ContentUnavailableView(
                    appLanguage.localized(.repository.pathNormalizationWaiting),
                    systemImage: "character.book.closed"
                )
            }
        }
    }

    private func targetRow(_ target: SVNRepositoryPathNormalizationTarget) -> some View {
        let differences = repositoryPathNormalizationComponentDifferences(
            repositoryPath: target.repositoryPath,
            normalizedPath: target.normalizedPath
        )

        return Toggle(
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
                        ? appLanguage.localized(.ui.folder.label)
                        : appLanguage.localized(.ui.file.labelFile2),
                    systemImage: target.isDirectory ? "folder.fill" : "doc.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    pathRow(
                        appLanguage.localized(.repository.pathNormalizationBefore),
                        path: target.repositoryPath
                    )
                    pathRow(
                        appLanguage.localized(.repository.pathNormalizationAfter),
                        path: target.normalizedPath
                    )
                }
                if !differences.isEmpty {
                    Divider()
                    ForEach(differences, id: \.componentIndex) { difference in
                        componentDifference(difference)
                    }
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(path)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                normalizationFormBadge(repositoryPathNormalizationForm(of: path))
            }
        }
    }

    private func normalizationFormBadge(
        _ form: RepositoryPathNormalizationForm
    ) -> some View {
        Text(normalizationFormLabel(form))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
            .fixedSize()
    }

    private func componentDifference(
        _ difference: RepositoryPathNormalizationComponentDifference
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text(appLanguage.localized(.repository.pathNormalizationDifferentComponent))
                    .foregroundStyle(.secondary)
                Text(difference.normalizedDifference)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            codePointRow(
                appLanguage.localized(.repository.pathNormalizationBefore),
                component: difference.repositoryDifference,
                summary: difference.repositoryCodePoints
            )
            codePointRow(
                appLanguage.localized(.repository.pathNormalizationAfter),
                component: difference.normalizedDifference,
                summary: difference.normalizedCodePoints
            )
        }
        .padding(.top, 4)
    }

    private func codePointRow(
        _ label: String,
        component: String,
        summary: RepositoryPathCodePointSummary
    ) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.codePoints)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text(
                    appLanguage.localized(
                        .repository.pathNormalizationCodepointsDetail,
                        normalizationFormLabel(repositoryPathNormalizationForm(of: component)),
                        summary.scalarCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func normalizationFormLabel(
        _ form: RepositoryPathNormalizationForm
    ) -> String {
        switch form {
        case .decomposed:
            appLanguage.localized(.repository.pathNormalizationFormDecomposed)
        case .composed:
            appLanguage.localized(.repository.pathNormalizationFormComposed)
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
                appLanguage.localized(.repository.pathNormalizationProblem),
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
                    .repository.pathNormalizationResultSummary,
                    result.renamedTargets.count,
                    result.committedRevisions.count
                ),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            if !result.committedRevisions.isEmpty {
                Text(
                    appLanguage.localized(
                        .repository.pathNormalizationResultRevisions,
                        result.committedRevisions.joined(separator: ", ")
                    )
                )
                .textSelection(.enabled)
            }
        } header: {
            Text(appLanguage.localized(.repository.pathNormalizationResult))
        }

        if !result.skippedTargets.isEmpty {
            Section {
                Text(appLanguage.localized(.repository.pathNormalizationSkippedReason))
                    .foregroundStyle(.secondary)
                ForEach(result.skippedTargets) { target in
                    Text(target.repositoryPath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text(
                    appLanguage.localized(
                        .repository.pathNormalizationSkipped,
                        result.skippedTargets.count
                    )
                )
            }
        }
    }

    private var commitMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLanguage.localized(.ui.commit.message))
                .font(.headline)
            TextField(
                appLanguage.localized(.ui.commit.message),
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
                    appLanguage.localized(.repository.pathNormalizationRunning)
                )
                .controlSize(.small)
            }
            Spacer()
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                store.isShowingRepositoryPathNormalization = false
            }
            .disabled(store.isRepositoryPathNormalizationRunning)
            if shouldOfferRescan {
                Button(appLanguage.localized(.repository.pathNormalizationScanAgain)) {
                    Task { await store.beginRepositoryPathNormalization() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.isRepositoryPathNormalizationRunning)
            } else {
                Button(appLanguage.localized(.repository.pathNormalizationReviewAction)) {
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
                appLanguage.localized(.repository.pathNormalizationConfirmationTitle),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)

            warning(
                appLanguage.localized(
                    .repository.pathNormalizationConfirmationCommits,
                    selectedCount
                ),
                systemImage: "shippingbox.and.arrow.backward"
            )
            warning(
                appLanguage.localized(
                    .repository.pathNormalizationConfirmationDeleteAdd
                ),
                systemImage: "arrow.left.arrow.right"
            )
            warning(
                appLanguage.localized(
                    .repository.pathNormalizationConfirmationDirectory
                ),
                systemImage: "folder.badge.gearshape"
            )
            warning(
                appLanguage.localized(
                    .repository.pathNormalizationConfirmationTeam
                ),
                systemImage: "person.3"
            )

            GroupBox(appLanguage.localized(.ui.commit.message)) {
                Text(store.repositoryPathNormalizationCommitMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }

            Spacer()

            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                    store.isConfirmingRepositoryPathNormalization = false
                }
                // 경로마다 삭제+추가 커밋이 올라간다. Return은 취소만 실행한다.
                .keyboardShortcut(.defaultAction)
                Button {
                    Task { await store.normalizeSelectedRepositoryPaths() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(
                            .repository.pathNormalizationConfirmationRun,
                            selectedCount
                        ),
                        inProgressTitle: appLanguage.localized(
                            .repository.pathNormalizationRunning
                        ),
                        systemImage: "checkmark",
                        isInProgress: store.isNormalizingRepositoryPaths
                    )
                }
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
