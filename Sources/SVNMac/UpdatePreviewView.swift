import SVNCore
import SwiftUI

/// 작업 복사본을 변경하기 전에 서버에서 내려올 커밋을 확인시키는 안전 장치입니다.
struct UpdatePreviewView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone

    var body: some View {
        @Bindable var store = store
        let preview = store.recoveryState.updatePreview
        let commitRecovery: OutOfDateCommitRecoveryRequest? = if store.recoveryState
            .updatePreviewMode == .outOfDateCommitRecovery
        {
            store.recoveryState.outOfDateCommitRecoveryRequest
        } else {
            nil
        }
        let treatsAsOutOfDate = UpdatePreviewCommitRecoveryPolicy.treatsWorkingCopyAsOutOfDate(
            hasCommitRecovery: commitRecovery != nil,
            isWorkingCopyOutOfDate: store.isWorkingCopyOutOfDate
        )
        let hasRemoteUpdate = !store.remoteChanges.isEmpty || treatsAsOutOfDate
        VStack(spacing: 0) {
            HStack {
                Text(sheetTitle(commitRecovery)).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized(.ui.common.close)) { store.dismissUpdatePreview() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isUpdatingSelectedProject)
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
                            .ui.update.showingFirstCommits,
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
                    ProgressView(appLanguage.localized(.ui.update.checkingIncomingChanges))
                } else if preview.commits.isEmpty, let errorMessage = preview.errorMessage {
                    ContentUnavailableView(
                        appLanguage.localized(.ui.error.unableLoadChanges),
                        systemImage: "exclamationmark.triangle",
                        description: Text(previewFailureDescription(errorMessage))
                    )
                } else if preview.commits.isEmpty {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: treatsAsOutOfDate ? "arrow.down.circle" : "checkmark.circle",
                        description: Text(emptyStateDescription)
                    )
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if store.shouldOfferRepositoryTemporaryFileCleanup {
                    Toggle(
                        appLanguage.localized(.ui.update.addRepositoryTemporaryFileCleanupCommitAfterUpdating),
                        isOn: $store.cleansRepositoryTemporaryFilesAfterUpdate
                    )
                    .toggleStyle(.checkbox)
                    .help(appLanguage.localized(.ui.update.afterUpdateCandidateContentsVerifiedReviewFinalListBeforeAny))
                }

                HStack {
                    Text(appLanguage.localized(.ui.update.incomingChangesThatOverlapLocalEditsMayCreateSvnConflict))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if commitRecovery?.conflictedPaths.isEmpty == false {
                        Button(appLanguage.localized(.ui.update.goConflictResolution)) {
                            store.isShowingUpdatePreview = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else if preview.canRunUpdate(
                        hasRemoteChanges: hasRemoteUpdate,
                        isWorkingCopyOutOfDate: treatsAsOutOfDate
                    ) {
                        Button {
                            Task { await store.update() }
                        } label: {
                            ActionProgressLabel(
                                title: commitRecovery == nil
                                    ? appLanguage.localized(.ui.update.runUpdate)
                                    : appLanguage.localized(.ui.update.retryCommit),
                                inProgressTitle: appLanguage.localized(.ui.update.updating),
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
        .interactiveDismissDisabled(store.isUpdatingSelectedProject)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private func sheetTitle(_ recovery: OutOfDateCommitRecoveryRequest?) -> String {
        guard recovery != nil else {
            return appLanguage.localized(.ui.update.preview)
        }
        return appLanguage.localized(.ui.update.requiredBeforeCommit)
    }

    private func commitRecoveryNotice(_ recovery: OutOfDateCommitRecoveryRequest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            commitRecoverySummary(recovery)
            // 어떤 경로가 뒤처졌는지는 SVN 원문에만 있습니다. 그것이 없으면
            // 서버 변경이 없어 보이는데도 커밋이 거절된 이유를 추적할 수 없습니다.
            Text(recovery.details)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func commitRecoverySummary(_ recovery: OutOfDateCommitRecoveryRequest) -> some View {
        Label {
            if recovery.conflictedPaths.isEmpty {
                Text(appLanguage.localized(
                    .ui.update.commitMessageSelectedItemSavedIfUpdateCreatesNoConflicts,
                    recovery.paths.count
                ))
            } else {
                Text(appLanguage.localized(
                    .ui.update.createdConflictsSoCommitNotRetriedResolvePathsFirst,
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
                    .iconHelp(appLanguage.localized(
                        isExpanded
                            ? .ui.update.collapseCommitDetails
                            : .ui.update.expandCommitDetails,
                        entry.revision
                    ))
                Text("r\(entry.revision)").font(.headline.monospacedDigit())
                Spacer()
                if let date = entry.date {
                    Text(formattedHistoryDate(date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text(appLanguage.localized(.ui.history.commitTimeUnavailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label(
                    entry.author.isEmpty
                        ? appLanguage.localized(.ui.common.unknownAuthor)
                        : entry.author,
                    systemImage: "person"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                SVNLogMessageView(entry: entry)
                Text(appLanguage.localized(.ui.history.changedPaths, entry.changedPaths.count))
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
            .ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate,
            errorMessage
        )
    }

    private var emptyStateTitle: String {
        if store.recoveryState.updatePreviewMode == .outOfDateCommitRecovery {
            return appLanguage.localized(.ui.update.beforeRetryingCommit)
        }
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized(.ui.update.previewAvailableStatus)
        }
        return appLanguage.localized(.ui.update.noIncomingChanges)
    }

    private var emptyStateDescription: String {
        if store.recoveryState.updatePreviewMode == .outOfDateCommitRecovery {
            return appLanguage.localized(.ui.update.svnRequiresWorkingCopyUpdateConfirmUpdateRetryCommitSaved)
        }
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized(.ui.update.serverChangesInsidePendingDeletionMayNotAppearListRun)
        }
        return appLanguage.localized(.ui.update.workingCopyUpDateServer)
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
        case .added: appLanguage.localized(.ui.status.added)
        case .modified: appLanguage.localized(.ui.status.modified)
        case .deleted: appLanguage.localized(.ui.status.deleted)
        case .replaced: appLanguage.localized(.ui.status.replaced)
        case let .unknown(value): value
        }
    }
}
