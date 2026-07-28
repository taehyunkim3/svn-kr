import SwiftUI
import SVNCore

/// 작업 복사본을 변경하기 전에 서버에서 내려올 경로를 확인시키는 안전 장치입니다.
struct UpdatePreviewView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.localized("ui.update.preview.3e2a4411")).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List(store.remoteChanges) { entry in
                HStack {
                    remoteBadge(entry.item)
                    Text(entry.path).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            .overlay {
                if store.remoteChanges.isEmpty, store.isPreviewingSelectedProjectUpdate {
                    ProgressView(appLanguage.localized("ui.checking.incoming.changes.a7a217e2"))
                } else if store.remoteChanges.isEmpty {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: store.isWorkingCopyOutOfDate == true ? "arrow.down.circle" : "checkmark.circle",
                        description: Text(emptyStateDescription)
                    )
                }
            }

            Divider()
            HStack {
                Text(appLanguage.localized("ui.incoming.changes.that.overlap.local.edits.may.cr.a2bc4e0e"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.remoteChanges.isEmpty || store.isWorkingCopyOutOfDate == true {
                    Button(appLanguage.localized("ui.run.update.e17c8217")) { Task { await store.update() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isUpdatingSelectedProject)
                }
            }
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.updatePreviewSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var emptyStateTitle: String {
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized("ui.update.required.f846039b")
        }
        return appLanguage.localized("ui.no.incoming.changes.8302e8b6")
    }

    private var emptyStateDescription: String {
        if store.isWorkingCopyOutOfDate == true {
            return appLanguage.localized("ui.server.changes.inside.a.pending.deletion.may.not.475f8db6")
        }
        return appLanguage.localized("ui.the.working.copy.is.up.to.date.with.the.server.e31e447e")
    }

    private func remoteBadge(_ item: SVNStatusKind) -> some View {
        StatusBadge(
            label: item.rawValue.uppercased(),
            color: item == .deleted ? .red : .blue
        )
    }
}
