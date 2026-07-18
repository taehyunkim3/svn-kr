import SwiftUI
import SVNCore

/// 서버 커밋 기록과 로컬 작업 복사본의 기준 위치를 표시하는 전용 화면입니다.
/// ContentView는 탭 배치만 담당하고, 기록 행의 표현과 날짜 포맷은 이 타입이 소유합니다.
struct HistoryView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone

    /// DateFormatter는 생성 비용이 크므로 뷰 상태로 한 번 만들고 설정만 갱신해 재사용합니다.
    @State private var dateFormatter = DateFormatter()
    @State private var searchText = ""

    var body: some View {
        let timeline = SVNHistoryTimeline(logs: store.logs, workingCopyRevision: store.workingCopyRevision)
        WorkspaceSplitView(
            primaryMinWidth: AppLayout.historyPrimaryMinimumWidth,
            detailMinWidth: AppLayout.historyDetailMinimumWidth
        ) {
            VStack(spacing: 0) {
                historySummary
                historyList(timeline: timeline)
            }
        } detail: {
            HistoryRevisionDiffView()
        }
        .overlay {
            if store.logs.isEmpty {
                ContentUnavailableView(appLanguage.text("커밋 기록 없음", "No Commit History"), systemImage: "clock")
            }
        }
        .searchable(text: $searchText, prompt: appLanguage.text("작성자, 파일, 메시지, 리비전 검색", "Search author, file, message, or revision"))
    }

    // MARK: - 기록 요약

    @ViewBuilder
    private var historySummary: some View {
        if let headRevision = store.logs.first?.revision {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Label(appLanguage.text("서버 최신 r\(headRevision)", "Server latest r\(headRevision)"), systemImage: "cloud")
                    if let workingCopyRevision = store.workingCopyRevision {
                        Label(appLanguage.text("내 로컬 폴더 r\(workingCopyRevision)", "My local folder r\(workingCopyRevision)"), systemImage: "macbook")
                        if store.isWorkingCopyOutOfDate == true {
                            Text(appLanguage.text("업데이트 필요", "Update required")).foregroundStyle(.orange)
                        } else if store.isWorkingCopyOutOfDate == false {
                            Text(appLanguage.text("최신", "Up to date")).foregroundStyle(.green)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 14) {
                    historyLegend(color: .blue, label: appLanguage.text("서버 커밋", "Server commit"))
                    historyLegend(color: .green, label: appLanguage.text("내 로컬 기준", "My local base"))
                    if !store.statuses.isEmpty {
                        historyLegend(color: .orange, label: appLanguage.text("미커밋 변경 \(store.statuses.count)개", "\(store.statuses.count) uncommitted changes"))
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
                    workingCopyMarkerRow(revision: revision, isBeforeLoadedHistory: false)
                }
                historyEntryRow(
                    entry,
                    index: index,
                    totalCount: entries.count,
                    timeline: timeline
                )
            }

            if searchText.isEmpty, let revision = store.workingCopyRevision, timeline.isBeforeLoadedHistory {
                workingCopyMarkerRow(revision: revision, isBeforeLoadedHistory: true)
            }

            if searchText.isEmpty, store.hasMoreHistory {
                HStack {
                    Spacer()
                    Button(appLanguage.text("이전 기록 50개 더 불러오기", "Load 50 More")) {
                        Task { await store.loadMoreHistory() }
                    }
                    .disabled(store.isWorking)
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
            let values = [entry.revision, entry.author, entry.email ?? "", entry.message]
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
                hasLocalChanges: isWorkingCopyEntry && !store.statuses.isEmpty
            )
            .frame(width: 76)
            .help(appLanguage.text(
                "파란 점은 서버 커밋, 초록 테두리는 내 로컬 기준, 주황 가지는 미커밋 변경을 뜻합니다.",
                "Blue dots are server commits, the green ring is your local base, and the orange branch is uncommitted work."
            ))

            VStack(alignment: .leading, spacing: 9) {
                historyEntryHeader(entry, isWorkingCopyEntry: isWorkingCopyEntry)
                historyAuthor(entry)
                Text(entry.message.isEmpty ? appLanguage.text("커밋 메시지 없음", "No commit message") : entry.message)
                    .textSelection(.enabled)
                changedPaths(entry.changedPaths)
                revisionProperties(entry.revisionProperties)
                Button {
                    store.selectHistoryRevision(entry.revision)
                } label: {
                    Label(appLanguage.text("이 커밋의 변경 내용 보기", "View Changes in This Commit"), systemImage: "doc.text.magnifyingglass")
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
                historyBadge(appLanguage.text("서버 최신", "Server latest"), color: .blue)
            }
            if isWorkingCopyEntry {
                historyBadge(workingCopyEntryBadge(for: entry.revision), color: .green)
                if !store.statuses.isEmpty {
                    historyBadge(appLanguage.text("로컬 변경 \(store.statuses.count)개", "\(store.statuses.count) local changes"), color: .orange)
                }
            }
            Spacer()
            if let date = entry.date {
                Text(formattedHistoryDate(date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(appLanguage.text("커밋 시각 없음", "Commit time unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func historyAuthor(_ entry: SVNLogEntry) -> some View {
        HStack(spacing: 12) {
            Label(entry.author.isEmpty ? appLanguage.text("작성자 없음", "Unknown author") : entry.author, systemImage: "person")
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
            DisclosureGroup(appLanguage.text("변경 경로 \(paths.count)개", "\(paths.count) changed paths")) {
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
            DisclosureGroup(appLanguage.text("추가 리비전 속성 \(properties.count)개", "\(properties.count) additional revision properties")) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(properties) { property in
                        HStack(alignment: .firstTextBaseline) {
                            Text(property.name).font(.caption.monospaced().bold())
                            Text(property.value.isEmpty ? appLanguage.text("값 없음", "No value") : property.value)
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
        entryRevision == store.workingCopyRevision
            ? appLanguage.text("내 로컬 기준", "My local base")
            : appLanguage.text("내 로컬에 포함", "Included locally")
    }

    private func workingCopyMarkerRow(revision: String, isBeforeLoadedHistory: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SVNHistoryGraphLane(
                isFirst: store.logs.isEmpty,
                isLast: isBeforeLoadedHistory,
                showsServerCommit: false,
                isWorkingCopyRevision: true,
                hasLocalChanges: !store.statuses.isEmpty
            )
            .frame(width: 76, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                if isBeforeLoadedHistory {
                    Text(appLanguage.text("… 이전 기록", "… Earlier history")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("r\(revision)").font(.headline.monospacedDigit())
                    historyBadge(appLanguage.text("내 로컬 기준", "My local base"), color: .green)
                    if !store.statuses.isEmpty {
                        historyBadge(appLanguage.text("로컬 변경 \(store.statuses.count)개", "\(store.statuses.count) local changes"), color: .orange)
                    }
                }
                Text(isBeforeLoadedHistory
                     ? appLanguage.text("내 로컬 기준 리비전이 최근 50개 서버 기록보다 이전입니다.", "Your local base revision is earlier than the latest 50 server records.")
                     : appLanguage.text("두 서버 커밋 사이의 내 로컬 갱신 기준입니다.", "Your local update base falls between two server commits."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func historyLegend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func historyBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - 날짜 포맷

    private var historyTimeZone: TimeZone {
        if historyTimeZoneIdentifier == AppSettings.systemHistoryTimeZone { return .current }
        return TimeZone(identifier: historyTimeZoneIdentifier)
            ?? TimeZone(identifier: AppSettings.defaultHistoryTimeZone)
            ?? .current
    }

    private func formattedHistoryDate(_ date: Date) -> String {
        dateFormatter.locale = Locale(identifier: appLanguage == .english ? "en_US_POSIX" : "ko_KR")
        dateFormatter.timeZone = historyTimeZone
        dateFormatter.dateFormat = "yyyy-MM-dd (EEE) HH:mm:ss.SSS"
        let abbreviation = historyTimeZoneIdentifier == "Asia/Seoul"
            ? "KST"
            : (historyTimeZone.abbreviation(for: date) ?? historyTimeZone.identifier)
        return "\(dateFormatter.string(from: date)) \(abbreviation)"
    }

    // MARK: - SVN 상태 표현 도우미

    private func changedPathBadge(_ action: SVNChangeAction) -> some View {
        Text(changedPathActionLabel(action))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(changedPathActionColor(action), in: Capsule())
    }

    @ViewBuilder
    private func changedPathDetails(_ changedPath: SVNChangedPath) -> some View {
        let details = [
            changedPath.kind.map { kind in
                switch kind {
                case .directory: appLanguage.text("폴더", "Folder")
                case .file: appLanguage.text("파일", "File")
                case let .unknown(value): value
                }
            },
            changedPath.textModified == true ? appLanguage.text("내용 변경", "Content changed") : nil,
            changedPath.propertiesModified == true ? appLanguage.text("속성 변경", "Properties changed") : nil,
        ].compactMap { $0 }
        if !details.isEmpty {
            Text(details.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
        }
        if let copyFromPath = changedPath.copyFromPath {
            Text(appLanguage.text(
                "복사 원본: \(copyFromPath)\(changedPath.copyFromRevision.map { "@r\($0)" } ?? "")",
                "Copied from: \(copyFromPath)\(changedPath.copyFromRevision.map { "@r\($0)" } ?? "")"
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }

    private func changedPathActionLabel(_ action: SVNChangeAction) -> String {
        switch action {
        case .added: appLanguage.text("추가", "Added")
        case .modified: appLanguage.text("수정", "Modified")
        case .deleted: appLanguage.text("삭제", "Deleted")
        case .replaced: appLanguage.text("교체", "Replaced")
        case let .unknown(value): value
        }
    }

    private func changedPathActionColor(_ action: SVNChangeAction) -> Color {
        switch action {
        case .added: .blue
        case .modified: .orange
        case .deleted: .red
        case .replaced: .purple
        case .unknown: .gray
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
        if hasLocalChanges { return appLanguage.text("내 로컬 기준 리비전에서 미커밋 변경이 갈라져 있습니다.", "Uncommitted changes branch from your local base revision.") }
        if isWorkingCopyRevision { return appLanguage.text("내 로컬 기준 리비전입니다.", "This is your local base revision.") }
        return appLanguage.text("서버 커밋입니다.", "This is a server commit.")
    }
}
