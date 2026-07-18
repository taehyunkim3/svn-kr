import SwiftUI

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

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if store.selectedHistoryRevision == nil {
            ContentUnavailableView(
                appLanguage.text("커밋을 선택하세요", "Select a Commit"),
                systemImage: "clock.arrow.circlepath",
                description: Text(appLanguage.text("기록에서 변경 내용 보기 버튼을 누르면 실제 diff가 표시됩니다.", "Choose View Changes in the history to display the actual diff."))
            )
        } else if isLoading {
            VStack {
                Spacer()
                ProgressView(appLanguage.text("변경 내용 불러오는 중…", "Loading changes…"))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Text(store.historyDiffContent.localizedText(appLanguage))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
    }

    private var isLoading: Bool {
        guard let projectID = store.selectedProjectID else { return false }
        return store.activeOperations.contains { $0.kind == .revisionDiff(projectID) }
    }
}
