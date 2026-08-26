import SwiftUI
import SVNCore

struct TreeConflictResolutionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChoice: TreeConflictResolutionChoice?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            if let session = store.activeTreeConflictSession {
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
                Task { await store.resolveActiveTreeConflict(using: choice) }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                pendingChoice = nil
            }
        } message: {
            if let choice = pendingChoice {
                Text(warningMessage(for: choice))
            }
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var header: some View {
        HStack {
            Label(
                appLanguage.localized(.ui.conflict.treeConflict),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)
            Spacer()
        }
    }

    private func conflictBody(_ session: TreeConflictSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.wasCanonicallyResolved {
                Label(
                    appLanguage.localized(.ui.conflict.macosUnicodePathMatchedActualSvnManagedPath),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(session.details.path.precomposedStringWithCanonicalMapping)
                .lineLimit(1)
                .textSelection(.enabled)

            if let description = TreeConflictPresentation.description(
                for: session.details,
                language: appLanguage
            ) {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(appLanguage.localized(.ui.conflict.treeConflictConcernsPathStateNotFileContentsNotChoice))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                choiceCard(
                    title: appLanguage.localized(.ui.conflict.keepMyChange),
                    description: appLanguage.localized(.ui.conflict.confirmCurrentWorkingCopyState),
                    warning: appLanguage.localized(
                        .ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer
                    ),
                    choice: .keepWorkingState
                )

                choiceCard(
                    title: appLanguage.localized(.ui.conflict.restoreFileServerVersion),
                    description: appLanguage.localized(
                        .ui.conflict.discardLocalChangeRestoreServerFile
                    ),
                    warning: appLanguage.localized(.ui.conflict.uncommittedLocalChangesDiscarded),
                    choice: .restoreServerVersion
                )
            }
        }
    }

    private func choiceCard(
        title: String,
        description: String,
        warning: String,
        choice: TreeConflictResolutionChoice
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                Text(description)
                    .foregroundStyle(.secondary)
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Spacer()
                    Button {
                        pendingChoice = choice
                    } label: {
                        ActionProgressLabel(
                            title: title,
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
        return title(for: choice)
    }

    private var confirmationActionTitle: String {
        guard let choice = pendingChoice else { return "" }
        return title(for: choice)
    }

    private func title(for choice: TreeConflictResolutionChoice) -> String {
        switch choice {
        case .keepWorkingState:
            appLanguage.localized(.ui.conflict.keepMyChange)
        case .restoreServerVersion:
            appLanguage.localized(.ui.conflict.restoreFileServerVersion)
        }
    }

    private func warningMessage(for choice: TreeConflictResolutionChoice) -> String {
        switch choice {
        case .keepWorkingState:
            return appLanguage.localized(.ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer)
        case .restoreServerVersion:
            return restoreWarningMessage(store.activeTreeConflictSession?.restoreImpact)
        }
    }

    /// 되돌리기는 하위 트리를 통째로 지우므로 개수만이 아니라 경로를 보여 줍니다.
    /// 저장소에 없는 파일이 먼저 오게 해서 영구 손실 항목을 눈에 띄게 합니다.
    private func restoreWarningMessage(_ impact: TreeConflictRestoreImpact?) -> String {
        guard let impact, !impact.isEmpty else {
            return appLanguage.localized(.ui.conflict.uncommittedLocalChangesDiscarded)
        }
        var lines = [appLanguage.localized(.ui.conflict.revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder)]
        lines += pathSection(
            title: appLanguage.localized(
                .ui.conflict.fileThatNotRepository,
                String(impact.unversionedPaths.count)
            ),
            paths: impact.unversionedPaths
        )
        lines += pathSection(
            title: appLanguage.localized(
                .ui.conflict.uncommittedChange,
                String(impact.uncommittedPaths.count)
            ),
            paths: impact.uncommittedPaths
        )
        return lines.joined(separator: "\n")
    }

    private func pathSection(title: String, paths: [String]) -> [String] {
        guard !paths.isEmpty else { return [] }
        let listed = paths.prefix(AppLayout.treeConflictRestoreListedPathLimit)
        var lines = [title]
        lines += listed.map { "  " + $0.precomposedStringWithCanonicalMapping }
        if paths.count > listed.count {
            lines.append("  " + appLanguage.localized(
                .ui.conflict.more,
                String(paths.count - listed.count)
            ))
        }
        return lines
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

enum TreeConflictPresentation {
    static func description(
        for details: SVNConflictDetails,
        language: AppLanguage
    ) -> String? {
        guard let localReason = details.treeConflictReason,
              let serverAction = details.treeConflictAction,
              let kind = details.treeConflictKind else { return nil }
        return language.localized(
            .ui.conflict.treeConflictLocalServerTarget,
            changeLabel(localReason, language: language),
            changeLabel(serverAction, language: language),
            kindLabel(kind, language: language)
        )
    }

    private static func changeLabel(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "edit", "edited": language.localized(.ui.status.modified)
        case "add", "added", "moved-here": language.localized(.ui.status.added)
        case "delete", "deleted", "missing", "moved-away": language.localized(.ui.status.deleted)
        case "replace", "replaced": language.localized(.ui.status.replaced)
        case "unversioned": language.localized(.ui.status.unversioned)
        case "obstructed": language.localized(.ui.update.localFileBlockingUpdate)
        default: value
        }
    }

    private static func kindLabel(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "file": language.localized(.ui.common.fileType)
        case "dir", "directory": language.localized(.ui.common.folder)
        default: value
        }
    }
}
