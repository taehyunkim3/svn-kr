import SwiftUI
import SVNCore

struct UntrackAndIgnoreRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let entry: SVNStatusEntry

    static func isEligible(_ entry: SVNStatusEntry) -> Bool {
        // `.`는 작업 복사본 루트라 `svn delete --keep-local` 대상이 될 수 없다.
        guard entry.path != ".", !entry.path.isEmpty else { return false }
        guard entry.propertyState != .conflicted else { return false }
        switch entry.item {
        case .modified, .added, .replaced:
            return true
        case .unknown(let raw) where raw == "normal":
            return true
        default:
            return false
        }
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
