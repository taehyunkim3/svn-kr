import SwiftUI

struct DeletionConfirmationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: DeletionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized("ui.mark.for.repository.deletion.3c417fc1"),
                systemImage: "trash"
            )
            .font(.title2.bold())

            Text(appLanguage.localized("ui.this.only.marks.the.items.for.deletion.they.are..594bb2c0"))

            if request.containsDirectory {
                Label(
                    appLanguage.localized("ui.versioned.items.below.the.selected.directory.wil.f7d01b47"),
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
                Text(appLanguage.localized("ui.item.s.7cb28e2a", request.entries.count))
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                    store.cancelDeletion()
                }
                // 저장소 삭제 예약은 Return으로 확정하지 않는다. Escape는 취소 역할이 맡는다.
                .keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    Task { await store.confirmDeletion(request) }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized("ui.mark.for.deletion.ec31cd20"),
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
