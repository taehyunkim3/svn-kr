import SwiftUI
import SVNCore

/// 선택한 서버 리비전의 실제 패치를 기록 목록과 분리해 표시합니다.
/// 바이너리 변경처럼 SVN이 텍스트 패치를 만들 수 없는 경우도 의미 있는 상태로 안내합니다.
struct HistoryRevisionDiffView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let revision = store.selectedHistoryRevision {
                    Label("r\(revision)", systemImage: "doc.text.magnifyingglass")
                        .font(.headline.monospacedDigit())
                } else {
                    Label(appLanguage.text("커밋 변경 내용", "Commit Changes"), systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
            Divider()

            stableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// 선택/로딩 상태가 바뀌어도 파일 목록과 diff 컨테이너 자체는 교체하지 않습니다.
    /// 컨테이너 타입을 유지해야 List와 placeholder의 고유 크기 차이로 패널이 재배치되지 않습니다.
    private var stableContent: some View {
        VStack(spacing: 0) {
            changedPathList(selectedEntry?.changedPaths ?? [])
                .frame(height: AppLayout.historyChangedFilesHeight)

            Divider()

            selectedPathDiff
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(selectedEntry == nil ? 0 : 1)
        .overlay {
            if store.selectedHistoryRevision == nil {
                ContentUnavailableView(
                    appLanguage.text("커밋을 선택하세요", "Select a Commit"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(appLanguage.text("기록에서 변경 내용 보기 버튼을 누르면 실제 diff가 표시됩니다.", "Choose View Changes in the history to display the actual diff."))
                )
            } else if selectedEntry == nil {
                ContentUnavailableView(
                    appLanguage.text("커밋 기록을 찾을 수 없습니다", "Commit Not Found"),
                    systemImage: "exclamationmark.magnifyingglass"
                )
            }
        }
    }

    @ViewBuilder
    private func changedPathList(_ paths: [SVNChangedPath]) -> some View {
        let files = paths.filter { changedPath in
            if case .directory? = changedPath.kind { return false }
            return true
        }
        if files.isEmpty {
            ContentUnavailableView(
                appLanguage.text("변경 파일 없음", "No Changed Files"),
                systemImage: "doc"
            )
        } else {
            List(files) { changedPath in
                Button {
                    guard let revision = store.selectedHistoryRevision else { return }
                    Task { await store.loadHistoryDiff(for: revision, changedPath: changedPath) }
                } label: {
                    HStack(spacing: 8) {
                        Text(changedPath.action.rawValue)
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(actionColor(changedPath.action))
                            .frame(width: 18)
                        Text(changedPath.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    store.selectedHistoryPath == changedPath.path
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear
                )
            }
        }
    }

    @ViewBuilder
    private var selectedPathDiff: some View {
        if store.selectedHistoryPath == nil {
            ContentUnavailableView(
                appLanguage.text("파일을 선택하세요", "Select a File"),
                systemImage: "doc.text.magnifyingglass",
                description: Text(appLanguage.text("위 목록에서 변경 파일을 선택하면 해당 파일의 diff만 표시됩니다.", "Choose a changed file above to display only that file's diff."))
            )
        } else if isLoading {
            VStack {
                Spacer()
                ProgressView(appLanguage.text("변경 내용 불러오는 중…", "Loading changes…"))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if case let .text(value) = store.historyDiffContent {
            diffText(value)
        } else {
            Text(store.historyDiffContent.localizedText(appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func diffText(_ value: String) -> some View {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        return ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(String(line))
                        .foregroundStyle(diffLineColor(line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding()
        }
    }

    private var selectedEntry: SVNLogEntry? {
        guard let revision = store.selectedHistoryRevision else { return nil }
        return store.logs.first { $0.revision == revision }
    }

    private func diffLineColor(_ line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        return .primary
    }

    private func actionColor(_ action: SVNChangeAction) -> Color {
        switch action {
        case .added: .green
        case .deleted: .red
        case .modified: .blue
        case .replaced: .orange
        case .unknown: .secondary
        }
    }

    private var isLoading: Bool {
        guard let projectID = store.selectedProjectID else { return false }
        return store.activeOperations.contains { $0.kind == .revisionDiff(projectID) }
    }
}
