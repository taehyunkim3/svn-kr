import SwiftUI

struct DeletionConfirmationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: DeletionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized(.ui.commit.markRepositoryDeletion),
                systemImage: "trash"
            )
            .font(.title2.bold())

            Text(appLanguage.localized(.ui.commit.onlyMarksItemsDeletionTheyDeletedSvnRepositoryWhenCommitted))

            if request.containsDirectory {
                Label(
                    appLanguage.localized(.ui.commit.versionedItemsBelowSelectedDirectoryAlsoMarkedDeletion),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            List(request.entries) { entry in
                HStack {
                    Image(systemName: entry.nodeKind == .directory ? "folder" : "doc")
                        .iconHelp(appLanguage.localized(
                            entry.nodeKind == .directory
                                ? .ui.browser.directory
                                : .ui.browser.fileAccessibilityLabel
                        ))
                    Text(entry.path.precomposedStringWithCanonicalMapping)
                        .font(.body.monospaced())
                }
            }

            HStack {
                Text(appLanguage.localized(.ui.commit.item, request.entries.count))
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.cancelDeletion()
                }
                .confirmationKeyboardShortcut(for: .cancel, behavior: .deletion)
                Button(role: .destructive) {
                    Task { await store.confirmDeletion(request) }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.commit.markDeletion),
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
