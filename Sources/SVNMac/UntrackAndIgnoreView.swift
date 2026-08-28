import SwiftUI
import SVNCore

struct UntrackAndIgnoreRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let entry: SVNStatusEntry

    static func isEligible(_ entry: SVNStatusEntry) -> Bool {
        entry.item != .unversioned
            && entry.item != .ignored
            && entry.item != .deleted
    }
}

struct UntrackAndIgnoreView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: UntrackAndIgnoreRequest
    @State private var propertyKind: SVNIgnorePropertyKind = .local

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized(.ui.ignore.untrackAndIgnoreTitle),
                systemImage: "eye.slash"
            )
            .font(.title2.bold())

            Text(appLanguage.localized(.ui.ignore.untrackAndIgnoreExplanation))

            Text(request.entry.path.precomposedStringWithCanonicalMapping)
                .font(.body.monospaced())
                .textSelection(.enabled)

            Picker(
                appLanguage.localized(.ui.ignore.propertyKind),
                selection: $propertyKind
            ) {
                Text("svn:ignore").tag(SVNIgnorePropertyKind.local)
                Text("svn:global-ignores").tag(SVNIgnorePropertyKind.global)
            }
            .pickerStyle(.radioGroup)

            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.cancelUntrackAndIgnore()
                }
                .confirmationKeyboardShortcut(for: .cancel, behavior: .deletion)
                Button(appLanguage.localized(.ui.ignore.untrackAndIgnore), role: .destructive) {
                    Task {
                        await store.untrackAndIgnore(request, propertyKind: propertyKind)
                    }
                }
                .disabled(store.isSelectedProjectActionBlocked)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.untrackAndIgnoreSheetMinimumSize)
        .interactiveDismissDisabled(store.isIgnoringSelectedProject)
    }
}
