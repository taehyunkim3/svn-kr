import SVNCore
import SwiftUI

/// 작업 복사본을 변경하기 전에 서버에서 내려올 커밋을 확인시키는 안전 장치입니다.
struct UpdatePreviewView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone

    var body: some View {
        @Bindable var store = store
        let preview = store.recoveryState.updatePreview
        let hasRemoteUpdate = !store.remoteChanges.isEmpty || store.isWorkingCopyOutOfDate == true
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.localized("ui.update.preview.3e2a4411")).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List {
                if preview.isTruncated {
                    Label(
                        appLanguage.localized(
                            "ui.showing.first.commits.of.total.8d6f4a21",
                            UpdatePreviewState.maximumVisibleCommitCount,
                            preview.totalCommitCount
                        ),
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }

                if let errorMessage = preview.errorMessage, !preview.commits.isEmpty {
                    previewError(errorMessage)
                }

                ForEach(preview.commits) { entry in
                    commitRow(entry)
                }
            }
            .overlay {
                if preview.commits.isEmpty, store.isPreviewingSelectedProjectUpdate {
                    ProgressView(appLanguage.localized("ui.checking.incoming.changes.a7a217e2"))
                } else if preview.commits.isEmpty, let errorMessage = preview.errorMessage {
                    ContentUnavailableView(
                        appLanguage.localized("ui.unable.to.load.changes.78b04452"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(previewFailureDescription(errorMessage))
                    )
                } else if preview.commits.isEmpty {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: store.isWorkingCopyOutOfDate == true ? "arrow.down.circle" : "checkmark.circle",
                        description: Text(emptyStateDescription)
                    )
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if store.shouldOfferRepositoryTemporaryFileCleanup {
                    Toggle(
                        appLanguage.localized("ui.add.repository.temporary.file.cleanup.commit.a19da94a"),
                        isOn: $store.cleansRepositoryTemporaryFilesAfterUpdate
                    )
                    .toggleStyle(.checkbox)
                    .help(appLanguage.localized("ui.after.update.verify.candidates.then.review.and.c.89b37719"))
                }

                HStack {
                    Text(appLanguage.localized("ui.incoming.changes.that.overlap.local.edits.may.cr.a2bc4e0e"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if preview.canRunUpdate(
                        hasRemoteChanges: hasRemoteUpdate,
                        isWorkingCopyOutOfDate: false
                    ) {
                        Button {
                            Task { await store.update() }
                        } label: {
                            ActionProgressLabel(
                                title: appLanguage.localized("ui.run.update.e17c8217"),
                                inProgressTitle: appLanguage.localized("ui.updating.4d2f9a11"),
                                isInProgress: store.isUpdatingSelectedProject
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isUpdatingSelectedProject)
                    }
                }
            }
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.updatePreviewSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private func commitRow(_ entry: SVNLogEntry) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: entry.revision)) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.changedPaths) { changedPath in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StatusBadge(
                            label: changedPathActionLabel(changedPath.action),
                            color: changedPath.action.presentationColor,
                            verticalPadding: 2
                        )
                        Text(changedPath.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("r\(entry.revision)").font(.headline.monospacedDigit())
                    Spacer()
                    if let date = entry.date {
                        Text(formattedHistoryDate(date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text(appLanguage.localized("ui.commit.time.unavailable.59140fc5"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Label(
                    entry.author.isEmpty
                        ? appLanguage.localized("ui.unknown.author.511030fa")
                        : entry.author,
                    systemImage: "person"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                SVNLogMessageView(entry: entry)
                Text(appLanguage.localized("ui.changed.paths.89badc04", entry.changedPaths.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private func expansionBinding(for revision: String) -> Binding<Bool> {
        Binding(
            get: { store.recoveryState.updatePreview.isExpanded(revision) },
            set: { store.recoveryState.updatePreview.setExpanded($0, revision: revision) }
        )
    }

    private func previewError(_ errorMessage: String) -> some View {
        Label {
            Text(previewFailureDescription(errorMessage))
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.orange)
    }

    private func previewFailureDescription(_ errorMessage: String) -> String {
        appLanguage.localized(
            "ui.preview.failed.update.still.available.2c71be90",
            errorMessage
        )
    }

    private var emptyStateTitle: String {
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized("ui.update.required.f846039b")
        }
        return appLanguage.localized("ui.no.incoming.changes.8302e8b6")
    }

    private var emptyStateDescription: String {
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized("ui.server.changes.inside.a.pending.deletion.may.not.475f8db6")
        }
        return appLanguage.localized("ui.the.working.copy.is.up.to.date.with.the.server.e31e447e")
    }

    private var historyTimeZone: TimeZone {
        if historyTimeZoneIdentifier == AppSettings.systemHistoryTimeZone { return .current }
        return TimeZone(identifier: historyTimeZoneIdentifier)
            ?? TimeZone(identifier: AppSettings.defaultHistoryTimeZone)
            ?? .current
    }

    private func formattedHistoryDate(_ date: Date) -> String {
        HistoryDateFormatting.shared.string(
            from: date,
            language: appLanguage,
            timeZone: historyTimeZone,
            usesKSTAbbreviation: historyTimeZoneIdentifier == "Asia/Seoul"
        )
    }

    private func changedPathActionLabel(_ action: SVNChangeAction) -> String {
        switch action {
        case .added: appLanguage.localized("ui.added.0dce7328")
        case .modified: appLanguage.localized("ui.modified.01365bb2")
        case .deleted: appLanguage.localized("ui.deleted.6826dd28")
        case .replaced: appLanguage.localized("ui.replaced.6da39732")
        case let .unknown(value): value
        }
    }
}
