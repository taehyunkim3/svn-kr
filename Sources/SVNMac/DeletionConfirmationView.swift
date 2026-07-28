import SwiftUI

struct DeletionConfirmationView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    let request: DeletionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.text("저장소에서도 삭제로 표시", "Mark for Repository Deletion"),
                systemImage: "trash"
            )
            .font(.title2.bold())

            Text(appLanguage.text(
                "지금은 삭제 예정 상태로만 바뀝니다. 커밋하면 SVN 저장소에서 삭제되며, 커밋 전에는 취소하고 복원할 수 있습니다.",
                "This only marks the items for deletion. They are deleted from the SVN repository when committed, and can be restored before then."
            ))

            if request.containsDirectory {
                Label(
                    appLanguage.text(
                        "선택한 디렉터리 아래의 SVN 추적 항목도 함께 삭제 예정이 됩니다.",
                        "Versioned items below the selected directory will also be marked for deletion."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            List(request.entries) { entry in
                HStack {
                    Image(systemName: entry.nodeKind == .directory ? "folder" : "doc")
                    Text(entry.path.precomposedStringWithCanonicalMapping)
                        .font(.body.monospaced())
                }
            }

            HStack {
                Text(appLanguage.text(
                    "\(request.entries.count)개 항목",
                    "\(request.entries.count) item(s)"
                ))
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.text("취소", "Cancel"), role: .cancel) {
                    store.cancelDeletion()
                }
                .keyboardShortcut(.cancelAction)
                Button(appLanguage.text("저장소에서도 삭제로 표시", "Mark for Deletion"), role: .destructive) {
                    Task { await store.confirmDeletion(request) }
                }
                .disabled(store.isWorking)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.deletionConfirmationSheetMinimumSize)
    }
}
