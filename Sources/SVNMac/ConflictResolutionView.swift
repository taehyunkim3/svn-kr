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
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) { pendingChoice = nil }
        } message: {
            if let choice = pendingChoice {
                Text(confirmationMessage(for: choice))
            }
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var header: some View {
        HStack {
            Label(appLanguage.localized(.ui.resolve.conflictSecondary), systemImage: "exclamationmark.triangle.fill")
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
                    appLanguage.localized(.ui.the.macosUnicodePathWasMatchedToTheActual),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if session.hasPropertyConflict {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        appLanguage.localized(.ui.content.andPropertyConflictTogether),
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
                        appLanguage.localized(.ui.both.versionsWereCopiedToABackupFolderEdi),
                        systemImage: "externaldrive.badge.checkmark"
                    )
                    Text(appLanguage.localized(.ui.when.youChooseAVersionTheCurrentWorkingFi))
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized(.ui.localizationOpen.backupFolder), systemImage: "folder") {
                    store.openConflictBackupFolder()
                }
                .disabled(store.isResolvingConflict)
            }

            HStack(alignment: .top, spacing: 14) {
                versionCard(
                    title: appLanguage.localized(.ui.apply.serverVersion),
                    originalPath: session.details.path,
                    version: session.server,
                    openTitle: appLanguage.localized(.ui.localizationOpen.serverFile),
                    useTitle: appLanguage.localized(.ui.apply.serverVersion),
                    warning: appLanguage.localized(
                        .ui.replace.withTheServerFileYourLocalEditsLe
                    ),
                    choice: .theirsFull
                )

                versionCard(
                    title: appLanguage.localized(.ui.overwrite.withMine),
                    originalPath: session.details.path,
                    version: session.mine,
                    openTitle: appLanguage.localized(.ui.localizationOpen.myFile),
                    useTitle: appLanguage.localized(.ui.overwrite.withMine),
                    warning: appLanguage.localized(
                        .ui.server.versionChangesWillBeDiscarded
                    ),
                    choice: .mineFull
                )
            }

            if !session.isBinary {
                DisclosureGroup(isExpanded: $isWorkingFileExpanded) {
                    workingFileCard(session)
                } label: {
                    Text(appLanguage.localized(.ui.confirm.manuallyEditedContent))
                }
            }
        }
    }

    private func propertyNamesDescription(_ propertyNames: [String]) -> String {
        guard !propertyNames.isEmpty else {
            return appLanguage.localized(.ui.conflicted.propertyNameUnavailable)
        }
        return appLanguage.localized(
            .ui.conflicted.properties,
            propertyNames.joined(separator: ", ")
        )
    }

    private func workingFileCard(_ session: ConflictResolutionSession) -> some View {
        GroupBox(appLanguage.localized(.ui.current.workingFile)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.requestedPath.precomposedStringWithCanonicalMapping)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(appLanguage.localized(.ui.after.reviewingBothBackupsKeepTheContentCu))
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button {
                        pendingChoice = .working
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized(.ui.confirm.manuallyEditedContent),
                            inProgressTitle: appLanguage.localized(.ui.resolving.label),
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
                            inProgressTitle: appLanguage.localized(.ui.resolving.label),
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
            return appLanguage.localized(.ui.use.myFileQuestion)
        case .theirsFull:
            return appLanguage.localized(.ui.use.serverFileQuestion)
        case .working:
            return appLanguage.localized(.ui.use.currentWorkingFileQuestion)
        }
    }

    private var confirmationActionTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.localized(.ui.use.myFilePrimary)
        case .theirsFull:
            return appLanguage.localized(.ui.use.serverFilePrimary)
        case .working:
            return appLanguage.localized(.ui.use.currentWorkingFilePrimary)
        }
    }

    private func confirmationMessage(for choice: SVNConflictChoice) -> String {
        let base: String
        switch choice {
        case .mineFull:
            base = appLanguage.localized(.ui.keep.yourFileALaterCommitWillReplaceTheR)
        case .theirsFull:
            base = appLanguage.localized(.ui.replace.withTheServerFileYourLocalEditsLe)
        case .working:
            base = appLanguage.localized(.ui.keep.theFileCurrentlySavedInTheWorkingCop)
        }
        guard store.activeConflictSession?.hasPropertyConflict == true else { return base }
        // 한 번의 `svn resolve`가 내용과 속성 충돌을 같은 방향으로 함께 해결합니다.
        let propertyOutcome = choice == .theirsFull
            ? appLanguage.localized(.ui.server.propertiesAlsoApplied)
            : appLanguage.localized(.ui.my.propertiesAlsoKept)
        return base + "\n" + propertyOutcome
    }

    private func versionMetadata(for version: ConflictVersionBackup) -> String {
        if let revision = version.revision {
            return appLanguage.localized(.ui.server.revision, revision)
        }
        if let modificationDate = version.modificationDate {
            return appLanguage.localized(.ui.modified.labelFormatted, modificationDate.formatted(date: .abbreviated, time: .shortened))
        }
        return appLanguage.localized(.ui.modification.dateUnavailable)
    }

    private var footer: some View {
        HStack {
            Text(appLanguage.localized(.ui.this.fileCannotBeCommittedUntilItIsMarked))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appLanguage.localized(.ui.cancel.label)) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isResolvingConflict)
        }
    }
}
