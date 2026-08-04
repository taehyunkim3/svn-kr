import SwiftUI
import SVNCore

/// 파일 내용 충돌의 두 비교 버전 또는 현재 작업 파일을 안전하게 선택하도록 안내합니다.
struct ConflictResolutionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChoice: SVNConflictChoice?

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
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) { pendingChoice = nil }
        } message: {
            if let choice = pendingChoice {
                Text(confirmationMessage(for: choice))
            }
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var header: some View {
        HStack {
            Label(appLanguage.localized("ui.resolve.conflict.d9c365ea"), systemImage: "exclamationmark.triangle.fill")
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
                    appLanguage.localized("ui.the.macos.unicode.path.was.matched.to.the.actual.0575e471"),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        appLanguage.localized("ui.both.versions.were.copied.to.a.backup.folder.edi.259e47d5"),
                        systemImage: "externaldrive.badge.checkmark"
                    )
                    Text(appLanguage.localized("ui.when.you.choose.a.version.the.current.working.fi.70533c5a"))
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized("ui.open.backup.folder.d8faa2d5"), systemImage: "folder") {
                    store.openConflictBackupFolder()
                }
                .disabled(store.isResolvingConflict)
            }

            versionCard(
                title: appLanguage.localized("ui.my.file.e70a2b5b"),
                originalPath: session.details.path,
                version: session.mine,
                openTitle: appLanguage.localized("ui.open.my.file.537a87cb"),
                useTitle: appLanguage.localized("ui.use.my.file.36631b8e"),
                choice: .mineFull
            )

            versionCard(
                title: appLanguage.localized("ui.server.file.4c69a88d"),
                originalPath: session.details.path,
                version: session.server,
                openTitle: appLanguage.localized("ui.open.server.file.252d515b"),
                useTitle: appLanguage.localized("ui.use.server.file.30c6c26c"),
                choice: .theirsFull
            )

            workingFileCard(session)
        }
    }

    private func workingFileCard(_ session: ConflictResolutionSession) -> some View {
        GroupBox(appLanguage.localized("ui.current.working.file.669bd1d9")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.requestedPath.precomposedStringWithCanonicalMapping)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(appLanguage.localized("ui.after.reviewing.both.backups.keep.the.content.cu.94842c30"))
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button {
                        pendingChoice = .working
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized("ui.use.current.working.file.275f4c29"),
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
    }

    private func versionCard(
        title: String,
        originalPath: String,
        version: ConflictVersionBackup,
        openTitle: String,
        useTitle: String,
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
    }

    private var confirmationTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.localized("ui.use.my.file.d12a8b2d")
        case .theirsFull:
            return appLanguage.localized("ui.use.server.file.949587dc")
        case .working:
            return appLanguage.localized("ui.use.current.working.file.40ab0712")
        }
    }

    private var confirmationActionTitle: String {
        guard let choice = pendingChoice else { return "" }
        switch choice {
        case .mineFull:
            return appLanguage.localized("ui.use.my.file.36631b8e")
        case .theirsFull:
            return appLanguage.localized("ui.use.server.file.30c6c26c")
        case .working:
            return appLanguage.localized("ui.use.current.working.file.275f4c29")
        }
    }

    private func confirmationMessage(for choice: SVNConflictChoice) -> String {
        switch choice {
        case .mineFull:
            appLanguage.localized("ui.keep.your.file.a.later.commit.will.replace.the.r.f576fdeb")
        case .theirsFull:
            appLanguage.localized("ui.replace.with.the.server.file.your.local.edits.le.f08dec1d")
        case .working:
            appLanguage.localized("ui.keep.the.file.currently.saved.in.the.working.cop.aa08fa30")
        }
    }

    private func versionMetadata(for version: ConflictVersionBackup) -> String {
        if let revision = version.revision {
            return appLanguage.localized("ui.server.revision.c11b62aa", revision)
        }
        if let modificationDate = version.modificationDate {
            return appLanguage.localized("ui.modified.98221376", modificationDate.formatted(date: .abbreviated, time: .shortened))
        }
        return appLanguage.localized("ui.modification.date.unavailable.7b2ebc97")
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
