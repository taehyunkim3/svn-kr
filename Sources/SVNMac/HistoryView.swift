import SwiftUI
import SVNCore

/// 서버 커밋 기록과 로컬 작업 복사본의 기준 위치를 표시하는 전용 화면입니다.
/// ContentView는 탭 배치만 담당하고, 기록 행의 표현과 날짜 포맷은 이 타입이 소유합니다.
struct HistoryView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone

    @Binding var searchText: String

    var body: some View {
        let timeline = SVNHistoryTimeline(
            logs: store.logs,
            workingCopyRevision: store.workingCopyRevision?.timelineRevision
        )
        WorkspaceSplitView(
            primaryMinWidth: AppLayout.historyPrimaryMinimumWidth,
            detailMinWidth: AppLayout.historyDetailMinimumWidth
        ) {
            VStack(spacing: 0) {
                historySummary
                historyList(timeline: timeline)
            }
            .overlay {
                if store.logs.isEmpty, store.isHistoryLoading {
                    ProgressView(appLanguage.localized(.ui.history.loadingCommitHistory))
                } else if store.logs.isEmpty {
                    ContentUnavailableView(
                        appLanguage.localized(.ui.history.noCommitHistory),
                        systemImage: "clock"
                    )
                }
            }
        } detail: {
            HistoryRevisionDiffView()
        }
    }

    // MARK: - 기록 요약

    @ViewBuilder
    private var historySummary: some View {
        if let headRevision = store.logs.first?.revision {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Label(appLanguage.localized(.ui.history.serverLatestR, headRevision), systemImage: "cloud")
                    if let workingCopyRevision = store.workingCopyRevision {
                        Label(appLanguage.localized(.ui.history.myLocalFolderR, workingCopyRevision.displayValue), systemImage: "macbook")
                        if workingCopyRevision.isMixed {
                            historyBadge(appLanguage.localized(.ui.history.mixedRevisions), color: .gray)
                        }
                        if store.isWorkingCopyOutOfDate == false {
                            Text(appLanguage.localized(.ui.history.upDate)).foregroundStyle(.green)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 14) {
                    historyLegend(color: .blue, label: appLanguage.localized(.ui.history.serverCommitLegend))
                    historyLegend(color: .green, label: localRevisionLegendLabel)
                    if !store.visibleStatuses.isEmpty {
                        historyLegend(color: .orange, label: appLanguage.localized(.ui.history.uncommittedChanges, store.visibleStatuses.count))
                    }
                    Spacer()
                }
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 10)
            Divider()
        }
    }

    // MARK: - 타임라인 목록

    private func historyList(timeline: SVNHistoryTimeline) -> some View {
        let entries = filteredLogs
        return List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if searchText.isEmpty, timeline.insertionIndex == index, let revision = store.workingCopyRevision {
                    workingCopyMarkerRow(revision: revision.timelineRevision, isBeforeLoadedHistory: false)
                }
                historyEntryRow(
                    entry,
                    index: index,
                    totalCount: entries.count,
                    timeline: timeline
                )
            }

            if searchText.isEmpty, let revision = store.workingCopyRevision, timeline.isBeforeLoadedHistory {
                workingCopyMarkerRow(revision: revision.timelineRevision, isBeforeLoadedHistory: true)
            }

            if searchText.isEmpty, !store.logs.isEmpty, store.hasMoreHistory {
                HStack {
                    Spacer()
                    Button {
                        Task { await store.loadMoreHistory() }
                    } label: {
                        ActionProgressLabel(
                            title: appLanguage.localized(.ui.history.load50More),
                            inProgressTitle: appLanguage.localized(.ui.history.loading),
                            isInProgress: store.isLoadingMoreHistory
                        )
                    }
                    .disabled(store.isSelectedProjectActionBlocked || store.isLoadingMoreHistory)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var filteredLogs: [SVNLogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.logs }
        return store.logs.filter { entry in
            let values = [entry.revision, entry.author, entry.email ?? "", entry.message, entry.originalMessage ?? ""]
                + entry.changedPaths.map(\.path)
            return values.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func historyEntryRow(_ entry: SVNLogEntry, index: Int, totalCount: Int, timeline: SVNHistoryTimeline) -> some View {
        let isWorkingCopyEntry = entry.revision == timeline.graphEntryRevision
        return HStack(alignment: .top, spacing: 0) {
            SVNHistoryGraphLane(
                isFirst: index == 0,
                isLast: index == totalCount - 1 && (!searchText.isEmpty || !timeline.isBeforeLoadedHistory),
                showsServerCommit: true,
                isWorkingCopyRevision: isWorkingCopyEntry,
                hasLocalChanges: isWorkingCopyEntry && !store.visibleStatuses.isEmpty
            )
            .frame(width: 76)
            .help(historyGraphHelp)

            VStack(alignment: .leading, spacing: 9) {
                historyEntryHeader(entry, isWorkingCopyEntry: isWorkingCopyEntry)
                historyAuthor(entry)
                SVNLogMessageView(entry: entry)
                changedPaths(entry.changedPaths)
                revisionProperties(entry.revisionProperties)
                Button {
                    store.selectHistoryRevision(entry.revision)
                } label: {
                    Label(appLanguage.localized(.ui.history.viewChangesCommit), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .tint(store.selectedHistoryRevision == entry.revision ? .accentColor : nil)
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func historyEntryHeader(_ entry: SVNLogEntry, isWorkingCopyEntry: Bool) -> some View {
        HStack {
            Text("r\(entry.revision)").font(.headline.monospacedDigit())
            if entry.revision == store.logs.first?.revision {
                historyBadge(appLanguage.localized(.ui.history.serverLatest), color: .blue)
            }
            if isWorkingCopyEntry {
                historyBadge(workingCopyEntryBadge(for: entry.revision), color: .green)
                if !store.visibleStatuses.isEmpty {
                    historyBadge(appLanguage.localized(.ui.history.localChanges, store.visibleStatuses.count), color: .orange)
                }
            }
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
    }

    private func historyAuthor(_ entry: SVNLogEntry) -> some View {
        HStack(spacing: 12) {
            Label(entry.author.isEmpty ? appLanguage.localized(.ui.common.unknownAuthor) : entry.author, systemImage: "person")
            if let email = entry.email, !email.isEmpty {
                Label(email, systemImage: "envelope").textSelection(.enabled)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - 변경 경로와 리비전 속성

    @ViewBuilder
    private func changedPaths(_ paths: [SVNChangedPath]) -> some View {
        if !paths.isEmpty {
            DisclosureGroup(appLanguage.localized(.ui.history.changedPaths, paths.count)) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(paths) { changedPath in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            changedPathBadge(changedPath.action)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(changedPath.path).font(.caption.monospaced()).textSelection(.enabled)
                                changedPathDetails(changedPath)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func revisionProperties(_ properties: [SVNRevisionProperty]) -> some View {
        if !properties.isEmpty {
            DisclosureGroup(appLanguage.localized(.ui.history.additionalRevisionProperties, properties.count)) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(properties) { property in
                        HStack(alignment: .firstTextBaseline) {
                            Text(property.name).font(.caption.monospaced().bold())
                            Text(property.value.isEmpty ? appLanguage.localized(.ui.history.noValue) : property.value)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
    }

    // MARK: - 타임라인 표현 도우미

    private func workingCopyEntryBadge(for entryRevision: String) -> String {
        if store.workingCopyRevision?.isMixed == true {
            return appLanguage.localized(.ui.history.highestLocalRevision)
        }
        return entryRevision == store.workingCopyRevision?.timelineRevision
            ? appLanguage.localized(.ui.history.myLocalBase)
            : appLanguage.localized(.ui.history.includedLocally)
    }

    private func workingCopyMarkerRow(revision: String, isBeforeLoadedHistory: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SVNHistoryGraphLane(
                isFirst: store.logs.isEmpty,
                isLast: isBeforeLoadedHistory,
                showsServerCommit: false,
                isWorkingCopyRevision: true,
                hasLocalChanges: !store.visibleStatuses.isEmpty
            )
            .frame(width: 76, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                if isBeforeLoadedHistory {
                    Text(appLanguage.localized(.ui.history.earlierHistory)).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("r\(revision)").font(.headline.monospacedDigit())
                    historyBadge(localRevisionMarkerLabel, color: .green)
                    if !store.visibleStatuses.isEmpty {
                        historyBadge(appLanguage.localized(.ui.history.localChanges, store.visibleStatuses.count), color: .orange)
                    }
                }
                Text(localRevisionMarkerDescription(isBeforeLoadedHistory: isBeforeLoadedHistory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private var localRevisionLegendLabel: String {
        store.workingCopyRevision?.isMixed == true
            ? appLanguage.localized(.ui.history.highestLocalRevision)
            : appLanguage.localized(.ui.history.myLocalBase)
    }

    private var localRevisionMarkerLabel: String {
        localRevisionLegendLabel
    }

    private var historyGraphHelp: String {
        if store.workingCopyRevision?.isMixed == true {
            return appLanguage.localized(.ui.history.blueDotsServerCommitsGreenRingHighestLocalRevisionOrange)
        }
        return appLanguage.localized(.ui.history.blueDotsServerCommitsGreenRingLocalBaseOrangeBranch)
    }

    private func localRevisionMarkerDescription(isBeforeLoadedHistory: Bool) -> String {
        if let revision = store.workingCopyRevision, revision.isMixed {
            return appLanguage.localized(.ui.history.workingCopyContainsMixedRevisionsRMarkerShowsHighestRevision, revision.displayValue)
        }
        return isBeforeLoadedHistory
            ? appLanguage.localized(.ui.history.localBaseRevisionEarlierThanLatest50ServerRecords)
            : appLanguage.localized(.ui.history.localUpdateBaseFallsBetweenTwoServerCommits)
    }

    private func historyLegend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func historyBadge(_ label: String, color: Color) -> some View {
        StatusBadge(label: label, color: color, style: .tinted)
    }

    // MARK: - 날짜 포맷

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

    // MARK: - SVN 상태 표현 도우미

    private func changedPathBadge(_ action: SVNChangeAction) -> some View {
        StatusBadge(
            label: changedPathActionLabel(action),
            color: action.presentationColor,
            verticalPadding: 2
        )
    }

    @ViewBuilder
    private func changedPathDetails(_ changedPath: SVNChangedPath) -> some View {
        let details = [
            changedPath.kind.map { kind in
                switch kind {
                case .directory: appLanguage.localized(.ui.common.folder)
                case .file: appLanguage.localized(.ui.common.fileType)
                case let .unknown(value): value
                }
            },
            changedPath.textModified == true ? appLanguage.localized(.ui.history.contentChanged) : nil,
            changedPath.propertiesModified == true ? appLanguage.localized(.ui.history.propertiesChanged) : nil,
        ].compactMap { $0 }
        if !details.isEmpty {
            Text(details.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
        }
        if let copyFromPath = changedPath.copyFromPath {
            Text(appLanguage.localized(
                .history.copy.copiedFrom,
                copyFromPath,
                changedPath.copyFromRevision.map { "@r\($0)" } ?? ""
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
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

/// 서버 커밋, 로컬 기준, 미커밋 변경의 관계를 한 행의 Canvas에 그립니다.
private struct SVNHistoryGraphLane: View {
    @Environment(\.appLanguage) private var appLanguage
    let isFirst: Bool
    let isLast: Bool
    let showsServerCommit: Bool
    let isWorkingCopyRevision: Bool
    let hasLocalChanges: Bool

    var body: some View {
        Canvas { context, size in
            let serverX: CGFloat = 22
            let localX: CGFloat = 58
            let nodeY: CGFloat = min(24, size.height / 2)
            var serverLine = Path()
            serverLine.move(to: CGPoint(x: serverX, y: isFirst ? nodeY : 0))
            serverLine.addLine(to: CGPoint(x: serverX, y: isLast ? nodeY : size.height))
            context.stroke(serverLine, with: .color(.secondary.opacity(0.35)), lineWidth: 2)

            if showsServerCommit {
                context.fill(Path(ellipseIn: CGRect(x: serverX - 5, y: nodeY - 5, width: 10, height: 10)), with: .color(.blue))
            }
            if isWorkingCopyRevision {
                context.stroke(Path(ellipseIn: CGRect(x: serverX - 9, y: nodeY - 9, width: 18, height: 18)), with: .color(.green), lineWidth: 3)
            }
            if hasLocalChanges {
                var branch = Path()
                branch.move(to: CGPoint(x: serverX + 5, y: nodeY))
                branch.addCurve(to: CGPoint(x: localX, y: nodeY), control1: CGPoint(x: serverX + 18, y: nodeY), control2: CGPoint(x: localX - 16, y: nodeY))
                context.stroke(branch, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                context.fill(Path(ellipseIn: CGRect(x: localX - 5, y: nodeY - 5, width: 10, height: 10)), with: .color(.orange))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if hasLocalChanges { return appLanguage.localized(.ui.history.uncommittedChangesBranchLocalBaseRevision) }
        if isWorkingCopyRevision { return appLanguage.localized(.ui.history.localBaseRevision) }
        return appLanguage.localized(.ui.history.serverCommitDetail)
    }
}
