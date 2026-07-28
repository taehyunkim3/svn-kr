import SwiftUI

struct FileHistoryView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(appLanguage.text("파일 커밋 기록", "File Commit History")).font(.title2.bold())
                    if let path = store.fileHistoryPath { Text(path).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(appLanguage.text("닫기", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List(store.fileHistory) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("r\(entry.revision)").font(.headline.monospacedDigit())
                        Label(entry.author, systemImage: "person").font(.caption)
                        Spacer()
                        if let date = entry.date { Text(date.formatted(date: .numeric, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                    }
                        SVNLogMessageView(entry: entry)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if store.fileHistory.isEmpty, store.isLoadingSelectedFileHistory {
                    ProgressView(appLanguage.text("파일 기록 불러오는 중…", "Loading file history…"))
                } else if store.fileHistory.isEmpty {
                    ContentUnavailableView(appLanguage.text("커밋 기록 없음", "No File History"), systemImage: "clock")
                }
            }
        }
        .appSheetFrame(minimumSize: AppLayout.fileHistorySheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }
}
