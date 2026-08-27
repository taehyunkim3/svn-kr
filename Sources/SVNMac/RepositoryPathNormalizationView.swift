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
                appLanguage.localized(.repository.pathNormalization.title),
                systemImage: "character.book.closed"
            )
            .font(.title2.bold())
            Spacer()
            Button(appLanguage.localized(.ui.common.close), role: .cancel) {
                store.isShowingRepositoryPathNormalization = false
            }
            .confirmationKeyboardShortcut(
                for: .cancel,
                behavior: .repositoryPathNormalizationDismissal
            )
            .disabled(store.isRepositoryPathNormalizationRunning)
        }
        .padding()
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                appLanguage.localized(.repository.pathNormalization.windowsNote),
                systemImage: "desktopcomputer"
            )
            Label(
                appLanguage.localized(.repository.pathNormalization.sameAppearanceNote),
                systemImage: "info.circle"
            )
            Label(
                appLanguage.localized(.repository.pathNormalization.directoryNote),
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
                    .ui.common.selectedCount,
                    store.selectedRepositoryPathNormalizationTargets.count
                )
            )
            .foregroundStyle(.secondary)
            Spacer()
            Button(
                store.allRepositoryPathNormalizationTargetsAreSelected
                    ? appLanguage.localized(.repository.pathNormalization.deselectAll)
                    : appLanguage.localized(.ui.commit.selectAll)
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
                Section(appLanguage.localized(.repository.pathNormalization.targets)) {
                    ForEach(store.repositoryPathNormalizationTargets) { target in
                        targetRow(target)
                    }
                }
            }
        }
        .overlay {
            if store.isScanningRepositoryPaths {
                ProgressView(
                    appLanguage.localized(.repository.pathNormalization.scanningDetail)
                )
            } else if store.repositoryPathNormalizationTargets.isEmpty,
                      store.repositoryPathNormalizationIssue == nil {
                ContentUnavailableView(
                    appLanguage.localized(.repository.pathNormalization.waiting),
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
                        ? appLanguage.localized(.ui.common.folder)
                        : appLanguage.localized(.ui.common.fileType),
                    systemImage: target.isDirectory ? "folder.fill" : "doc.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    pathRow(
                        appLanguage.localized(.repository.pathNormalization.before),
                        path: target.repositoryPath,
                        comparedTo: target.normalizedPath,
                        differenceColor: .orange
                    )
                    pathRow(
                        appLanguage.localized(.repository.pathNormalization.after),
                        path: target.normalizedPath,
                        comparedTo: target.repositoryPath,
                        differenceColor: .accentColor
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

    private func pathRow(
        _ label: String,
        path: String,
        comparedTo comparisonPath: String,
        differenceColor: Color
    ) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                highlightedPath(
                    path,
                    comparedTo: comparisonPath,
                    differenceColor: differenceColor
                )
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                normalizationFormBadge(repositoryPathNormalizationForm(of: path))
            }
        }
    }

    private func highlightedPath(
        _ path: String,
        comparedTo comparisonPath: String,
        differenceColor: Color
    ) -> Text {
        var attributedPath = AttributedString()
        for segment in repositoryPathDifferenceSegments(
            path: path,
            comparedTo: comparisonPath
        ) {
            var attributedSegment = AttributedString(segment.text)
            attributedSegment.foregroundColor = segment.isDifferent
                ? differenceColor
                : .primary
            attributedPath.append(attributedSegment)
        }
        return Text(attributedPath)
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
                Text(appLanguage.localized(.repository.pathNormalization.differentComponent))
                    .foregroundStyle(.secondary)
                Text(difference.normalizedDifference)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            codePointRow(
                appLanguage.localized(.repository.pathNormalization.before),
                component: difference.repositoryDifference,
                summary: difference.repositoryCodePoints
            )
            codePointRow(
                appLanguage.localized(.repository.pathNormalization.after),
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
                        .repository.pathNormalization.codepointsDetail,
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
            appLanguage.localized(.repository.pathNormalization.formDecomposed)
        case .composed:
            appLanguage.localized(.repository.pathNormalization.formComposed)
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
                appLanguage.localized(.repository.pathNormalization.problem),
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
                    .repository.pathNormalization.resultSummary,
                    result.renamedTargets.count,
                    result.committedRevisions.count
                ),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            if !result.committedRevisions.isEmpty {
                Text(
                    appLanguage.localized(
                        .repository.pathNormalization.resultRevisions,
                        result.committedRevisions.joined(separator: ", ")
                    )
                )
                .textSelection(.enabled)
            }
        } header: {
            Text(appLanguage.localized(.repository.pathNormalization.result))
        }

        if !result.skippedTargets.isEmpty {
            Section {
                Text(appLanguage.localized(.repository.pathNormalization.skippedReason))
                    .foregroundStyle(.secondary)
                ForEach(result.skippedTargets) { target in
                    Text(target.repositoryPath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text(
                    appLanguage.localized(
                        .repository.pathNormalization.skipped,
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
                    appLanguage.localized(.repository.pathNormalization.running)
                )
                .controlSize(.small)
            }
            Spacer()
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.isShowingRepositoryPathNormalization = false
            }
            .disabled(store.isRepositoryPathNormalizationRunning)
            if shouldOfferRescan {
                Button(appLanguage.localized(.repository.pathNormalization.scanAgain)) {
                    Task { await store.beginRepositoryPathNormalization() }
                }
                .confirmationKeyboardShortcut(
                    for: .rescanRepositoryPaths,
                    behavior: .repositoryPathNormalizationRescan
                )
                .disabled(store.isRepositoryPathNormalizationRunning)
            } else {
                Button(appLanguage.localized(.repository.pathNormalization.reviewAction)) {
                    store.requestRepositoryPathNormalizationConfirmation()
                }
                .confirmationKeyboardShortcut(
                    for: .reviewRepositoryPathNormalization,
                    behavior: .repositoryPathNormalizationReview
                )
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
                appLanguage.localized(.repository.pathNormalization.confirmationTitle),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)

            warning(
                appLanguage.localized(
                    .repository.pathNormalization.confirmationCommits,
                    selectedCount
                ),
                systemImage: "shippingbox.and.arrow.backward"
            )
            warning(
                appLanguage.localized(
                    .repository.pathNormalization.confirmationDeleteAdd
                ),
                systemImage: "arrow.left.arrow.right"
            )
            warning(
                appLanguage.localized(
                    .repository.pathNormalization.confirmationDirectory
                ),
                systemImage: "folder.badge.gearshape"
            )
            warning(
                appLanguage.localized(
                    .repository.pathNormalization.confirmationTeam
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
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.isConfirmingRepositoryPathNormalization = false
                }
                .confirmationKeyboardShortcut(
                    for: .cancel,
                    behavior: .repositoryPathNormalization
                )
                Button {
                    Task { await store.normalizeSelectedRepositoryPaths() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(
                            .repository.pathNormalization.confirmationRun,
                            selectedCount
                        ),
                        inProgressTitle: appLanguage.localized(
                            .repository.pathNormalization.running
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
