import SwiftUI

struct DeletionConfirmationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: DeletionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized(.ui.mark.forRepositoryDeletion),
                systemImage: "trash"
            )
            .font(.title2.bold())

            Text(appLanguage.localized(.ui.this.onlyMarksTheItemsForDeletionTheyAre))

            if request.containsDirectory {
                Label(
                    appLanguage.localized(.ui.versioned.itemsBelowTheSelectedDirectoryWil),
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
                Text(appLanguage.localized(.ui.item.s, request.entries.count))
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                    store.cancelDeletion()
                }
                // 저장소 삭제 예약은 Return으로 확정하지 않는다. Escape는 취소 역할이 맡는다.
                .keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    Task { await store.confirmDeletion(request) }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.mark.forDeletion),
                        isInProgress: store.isDeletingSelectedProject
                    )
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.deletionConfirmationSheetMinimumSize)
    }
}
