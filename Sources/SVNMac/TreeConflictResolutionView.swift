import SwiftUI

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
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
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
                appLanguage.localized("ui.tree.conflict.2ea1184c"),
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
                    appLanguage.localized("ui.the.macos.unicode.path.was.matched.to.the.actual.0575e471"),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(session.details.path.precomposedStringWithCanonicalMapping)
                .lineLimit(1)
                .textSelection(.enabled)

            Text(appLanguage.localized("ui.tree.conflict.is.not.a.choice.between.two.files.66dcb7a1"))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                choiceCard(
                    title: appLanguage.localized("ui.keep.my.change.14f3a8c6"),
                    description: appLanguage.localized("ui.confirm.current.working.copy.state.1c63f80b"),
                    warning: appLanguage.localized(
                        "ui.local.deletion.will.remain.and.a.commit.will.de.837b94a0"
                    ),
                    choice: .keepWorkingState
                )

                choiceCard(
                    title: appLanguage.localized("ui.restore.file.from.server.version.4dd51eb7"),
                    description: appLanguage.localized(
                        "ui.discard.local.change.and.restore.server.file.728e0bf1"
                    ),
                    warning: appLanguage.localized("ui.local.changes.will.be.discarded.5e8127cf"),
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
                            inProgressTitle: appLanguage.localized("ui.resolving.d5e0b71c"),
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
            appLanguage.localized("ui.keep.my.change.14f3a8c6")
        case .restoreServerVersion:
            appLanguage.localized("ui.restore.file.from.server.version.4dd51eb7")
        }
    }

    private func warningMessage(for choice: TreeConflictResolutionChoice) -> String {
        switch choice {
        case .keepWorkingState:
            return appLanguage.localized("ui.local.deletion.will.remain.and.a.commit.will.de.837b94a0")
        case .restoreServerVersion:
            return restoreWarningMessage(store.activeTreeConflictSession?.restoreImpact)
        }
    }

    /// 되돌리기는 하위 트리를 통째로 지우므로 개수만이 아니라 경로를 보여 줍니다.
    /// 저장소에 없는 파일이 먼저 오게 해서 영구 손실 항목을 눈에 띄게 합니다.
    private func restoreWarningMessage(_ impact: TreeConflictRestoreImpact?) -> String {
        guard let impact, !impact.isEmpty else {
            return appLanguage.localized("ui.local.changes.will.be.discarded.5e8127cf")
        }
        var lines = [appLanguage.localized("ui.restore.server.version.removes.these.items.9d41c60b")]
        lines += pathSection(
            title: appLanguage.localized(
                "ui.files.not.in.repository.count.2b7fa508",
                String(impact.unversionedPaths.count)
            ),
            paths: impact.unversionedPaths
        )
        lines += pathSection(
            title: appLanguage.localized(
                "ui.uncommitted.changes.count.7e3c19d4",
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
                "ui.and.more.items.count.a5d20f16",
                String(paths.count - listed.count)
            ))
        }
        return lines
    }

    private var footer: some View {
        HStack {
            Text(appLanguage.localized("ui.this.file.cannot.be.committed.until.it.is.marked.201bfa2c"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appLanguage.localized("ui.cancel.a2ce2c22")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isResolvingConflict)
        }
    }
}
