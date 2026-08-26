import SwiftUI
import SVNCore

/// 파일 내용 충돌의 두 비교 버전 또는 현재 작업 파일을 안전하게 선택하도록 안내합니다.
struct ConflictResolutionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChoice: SVNConflictChoice?
    @State private var isWorkingFileExpanded = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            if let session = store.activeConflictSession {
                conflictBody(session)
            }
            Spacer()
            Divider()
            footer
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.conflictResolutionSheetMinimumSize)
        .interactiveDismissDisabled(store.isResolvingConflict)
        .alert(
            confirmationTitle,
            isPresented: .isPresenting($pendingChoice)
        ) {
            Button(confirmationActionTitle, role: .destructive) {
                guard let choice = pendingChoice else { return }
                pendingChoice = nil
                Task { await store.resolveActiveConflict(using: choice) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) { pendingChoice = nil }
        } message: {
            if let choice = pendingChoice {
                Text(confirmationMessage(for: choice))
            }
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var header: some View {
        HStack {
            Label(appLanguage.localized(.ui.conflict.resolutionHeader), systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Spacer()
        }
    }

    @ViewBuilder
    private func conflictBody(_ session: ConflictResolutionSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.wasCanonicallyResolved {
                Label(
                    appLanguage.localized(.ui.conflict.macosUnicodePathMatchedActualSvnManagedPath),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if session.hasPropertyConflict {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        appLanguage.localized(.ui.conflict.fileAlsoPropertyConflictChoosingVersionBelowResolvesPropertiesSame),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Text(propertyNamesDescription(session.propertyNames))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        appLanguage.localized(.ui.conflict.bothVersionsCopiedBackupFolderEditingCopiesDoesNotChange),
                        systemImage: "externaldrive.badge.checkmark"
                    )
                    Text(appLanguage.localized(.ui.conflict.whenChooseVersionCurrentWorkingFilePreservedSeparatelyHiddenRecovery))
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized(.ui.conflict.openBackupFolder), systemImage: "folder") {
                    store.openConflictBackupFolder()
                }
                .disabled(store.isResolvingConflict)
            }

            HStack(alignment: .top, spacing: 14) {
                versionCard(
                    title: appLanguage.localized(.ui.conflict.applyServerVersion),
                    originalPath: session.details.path,
                    version: session.server,
                    openTitle: appLanguage.localized(.ui.conflict.openServerFile),
                    useTitle: appLanguage.localized(.ui.conflict.applyServerVersion),
                    warning: appLanguage.localized(
                        .ui.conflict.replaceServerFileLocalEditsLeaveWorkingCopyButRemain
                    ),
                    choice: .theirsFull
                )

                versionCard(
                    title: appLanguage.localized(.ui.conflict.overwriteMyVersion),
                    originalPath: session.details.path,
                    version: session.mine,
                    openTitle: appLanguage.localized(.ui.conflict.openMyFile),
                    useTitle: appLanguage.localized(.ui.conflict.overwriteMyVersion),
                    warning: appLanguage.localized(
                        .ui.conflict.overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile
                    ),
                    choice: .mineFull
                )
            }

            if !session.isBinary {
                DisclosureGroup(isExpanded: $isWorkingFileExpanded) {
                    workingFileCard(session)
                } label: {
                    Text(appLanguage.localized(.ui.conflict.confirmManuallyEditedContent))
                }
            }
        }
    }

    private func propertyNamesDescription(_ propertyNames: [String]) -> String {
        guard !propertyNames.isEmpty else {
            return appLanguage.localized(.ui.conflict.conflictedPropertyNameCouldNotDetermined)
        }
        return appLanguage.localized(
            .ui.conflict.conflictedProperties,
            propertyNames.joined(separator: ", ")
        )
    }

    private func workingFileCard(_ session: ConflictResolutionSession) -> some View {
        GroupBox(appLanguage.localized(.ui.conflict.currentWorkingFile)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.requestedPath.precomposedStringWithCanonicalMapping)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(appLanguage.localized(.ui.conflict.afterReviewingBothBackupsKeepContentCurrentlySavedWorkingFile))
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button {
                        pendingChoice = .working
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized(.ui.conflict.confirmManuallyEditedContent),
                            inProgressTitle: appLanguage.localized(.ui.conflict.resolving),
                            isInProgress: store.isResolvingConflict
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isResolvingConflict)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func versionCard(
        title: String,
        originalPath: String,
        version: ConflictVersionBackup,
        openTitle: String,
        useTitle: String,
        warning: String,
        choice: SVNConflictChoice
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(originalPath.precomposedStringWithCanonicalMapping)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(version.url.lastPathComponent)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(ByteCountFormatter.string(fromByteCount: version.byteCount, countStyle: .file))
                    .foregroundStyle(.secondary)
                Text(versionMetadata(for: version))
                    .foregroundStyle(.secondary)
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Button(openTitle) {
                        store.openConflictVersion(choice)
                    }
                    .disabled(store.isResolvingConflict)
                    Spacer()
                    Button {
                        pendingChoice = choice
                    } label: {
                        ActionProgressLabel(
                            title: useTitle,
                            inProgressTitle: appLanguage.localized(.ui.conflict.resolving),
                            isInProgress: store.isResolvingConflict
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isResolvingConflict)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var confirmationTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.localized(.ui.conflict.useMineConfirmationTitle)
        case .theirsFull:
            return appLanguage.localized(.ui.conflict.useServerConfirmationTitle)
        case .working:
            return appLanguage.localized(.ui.conflict.useWorkingFileConfirmationTitle)
        }
    }

    private var confirmationActionTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.localized(.ui.conflict.useMineAction)
        case .theirsFull:
            return appLanguage.localized(.ui.conflict.useServerAction)
        case .working:
            return appLanguage.localized(.ui.conflict.useWorkingFileAction)
        }
    }

    private func confirmationMessage(for choice: SVNConflictChoice) -> String {
        let base: String
        switch choice {
        case .mineFull:
            base = appLanguage.localized(.ui.conflict.keepFileLaterCommitReplaceRepositoryFileContent)
        case .theirsFull:
            base = appLanguage.localized(.ui.conflict.replaceServerFileLocalEditsLeaveWorkingCopyButRemain)
        case .working:
            base = appLanguage.localized(.ui.conflict.keepFileCurrentlySavedWorkingCopyMarkConflictResolvedFile)
        }
        guard store.activeConflictSession?.hasPropertyConflict == true else { return base }
        // 한 번의 `svn resolve`가 내용과 속성 충돌을 같은 방향으로 함께 해결합니다.
        let propertyOutcome = choice == .theirsFull
            ? appLanguage.localized(.ui.conflict.serverPropertyValuesAppliedWell)
            : appLanguage.localized(.ui.conflict.propertyValuesKeptWell)
        return base + "\n" + propertyOutcome
    }

    private func versionMetadata(for version: ConflictVersionBackup) -> String {
        if let revision = version.revision {
            return appLanguage.localized(.ui.conflict.serverRevision, revision)
        }
        if let modificationDate = version.modificationDate {
            return appLanguage.localized(.ui.conflict.modified, modificationDate.formatted(date: .abbreviated, time: .shortened))
        }
        return appLanguage.localized(.ui.conflict.modificationDateUnavailable)
    }

    private var footer: some View {
        HStack {
            Text(appLanguage.localized(.ui.conflict.fileCannotCommittedUntilItMarkedResolved))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appLanguage.localized(.ui.common.cancel)) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isResolvingConflict)
        }
    }
}
