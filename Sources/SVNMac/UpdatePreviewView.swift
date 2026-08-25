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
        let commitRecovery = store.recoveryState.outOfDateCommitRecoveryRequest
        let hasRemoteUpdate = !store.remoteChanges.isEmpty || store.isWorkingCopyOutOfDate == true
        VStack(spacing: 0) {
            HStack {
                Text(sheetTitle(commitRecovery)).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List {
                if let commitRecovery {
                    commitRecoveryNotice(commitRecovery)
                }

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
                    if commitRecovery?.conflictedPaths.isEmpty == false {
                        Button(appLanguage.localized("ui.go.resolve.update.conflicts.2d9e4b71")) {
                            store.isShowingUpdatePreview = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else if preview.canRunUpdate(
                        hasRemoteChanges: hasRemoteUpdate,
                        isWorkingCopyOutOfDate: false
                    ) {
                        Button {
                            Task { await store.update() }
                        } label: {
                            ActionProgressLabel(
                                title: commitRecovery == nil
                                    ? appLanguage.localized("ui.run.update.e17c8217")
                                    : appLanguage.localized("ui.update.and.retry.commit.4c6f1a82"),
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

    private func sheetTitle(_ recovery: OutOfDateCommitRecoveryRequest?) -> String {
        guard recovery != nil else {
            return appLanguage.localized("ui.update.preview.3e2a4411")
        }
        return appLanguage.localized("ui.commit.requires.update.before.retry.91b7e3c5")
    }

    private func commitRecoveryNotice(_ recovery: OutOfDateCommitRecoveryRequest) -> some View {
        Label {
            if recovery.conflictedPaths.isEmpty {
                Text(appLanguage.localized(
                    "ui.commit.input.saved.update.then.retry.5e2a8d90",
                    recovery.paths.count
                ))
            } else {
                Text(appLanguage.localized(
                    "ui.update.conflicts.blocked.commit.retry.8b3d6f20",
                    recovery.conflictedPaths.joined(separator: ", ")
                ))
            }
        } icon: {
            Image(systemName: recovery.conflictedPaths.isEmpty
                ? "arrow.triangle.2.circlepath"
                : "exclamationmark.triangle")
        }
        .foregroundStyle(recovery.conflictedPaths.isEmpty ? Color.secondary : Color.orange)
    }

    private func commitRow(_ entry: SVNLogEntry) -> some View {
        let isExpanded = store.recoveryState.updatePreview.isExpanded(entry.revision)
        let indent = AppLayout.updatePreviewCommitDisclosureSize.width
            + AppLayout.updatePreviewCommitDisclosureSpacing
        return VStack(alignment: .leading, spacing: 7) {
            // 펼침 아이콘은 리비전 숫자와 같은 줄에 두어 세로 중앙을 맞춥니다.
            // 요약 여러 줄을 라벨로 묶으면 아이콘이 전체 높이 기준으로 정렬되어 어긋납니다.
            HStack(spacing: AppLayout.updatePreviewCommitDisclosureSpacing) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: AppLayout.updatePreviewCommitDisclosureSize.width,
                        height: AppLayout.updatePreviewCommitDisclosureSize.height
                    )
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

            VStack(alignment: .leading, spacing: 7) {
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

                if isExpanded {
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
            }
            .padding(.leading, indent)
        }
        .padding(.vertical, 6)
        // 아이콘뿐 아니라 행 전체를 눌러도 펼치고 접을 수 있어야 합니다.
        .contentShape(Rectangle())
        .onTapGesture {
            store.recoveryState.updatePreview.setExpanded(!isExpanded, revision: entry.revision)
        }
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
        if store.recoveryState.outOfDateCommitRecoveryRequest != nil {
            return appLanguage.localized("ui.update.required.before.commit.retry.3f8c1d67")
        }
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized("ui.update.required.f846039b")
        }
        return appLanguage.localized("ui.no.incoming.changes.8302e8b6")
    }

    private var emptyStateDescription: String {
        if store.recoveryState.outOfDateCommitRecoveryRequest != nil {
            return appLanguage.localized("ui.review.update.then.retry.commit.6a1e9c43")
        }
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
