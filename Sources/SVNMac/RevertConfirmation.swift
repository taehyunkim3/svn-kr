import SwiftUI

private struct RevertConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(
            appLanguage.localized(.ui.commit.revertLocalChangesConfirmationTitle),
            isPresented: .isPresenting($store.revertRequest),
            presenting: store.revertRequest
        ) { request in
            Button(appLanguage.localized(.ui.commit.revert), role: .destructive) { Task { await store.confirmRevert(request) } }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.revertRequest = nil
                store.revertImpactContext = nil
            }
            .confirmationKeyboardShortcut(for: .cancel, behavior: .revert)
        } message: { request in
            Text(message(for: request))
        }
    }

    /// `svn revert --depth infinity`는 대상 아래를 통째로 되돌립니다.
    /// 개수만으로는 무엇이 사라지는지 알 수 없으므로 경로를 함께 보여줍니다.
    private func message(for request: RevertRequest) -> String {
        if request.entry.item == .missing || request.entry.item == .deleted {
            return appLanguage.localized(
                .ui.commit.cancelRepositoryDeletionStateRestoreRepositoryVersionLocally,
                request.entry.path
            )
        }
        var lines = [
            appLanguage.localized(.ui.commit.uncommittedChangesDiscardedCannotRestoredSvn, request.entry.path),
        ]
        if let impact = store.revertImpact(for: request), !impact.isEmpty {
            lines.append(appLanguage.localized(.ui.conflict.revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder))
            lines += pathSection(
                title: appLanguage.localized(
                    .ui.conflict.fileThatNotRepository,
                    String(impact.unversionedPaths.count)
                ),
                paths: impact.unversionedPaths
            )
            lines += pathSection(
                title: appLanguage.localized(
                    .ui.conflict.uncommittedChange,
                    String(impact.uncommittedPaths.count)
                ),
                paths: impact.uncommittedPaths
            )
        }
        return lines.joined(separator: "\n")
    }

    private func pathSection(title: String, paths: [String]) -> [String] {
        guard !paths.isEmpty else { return [] }
        let listed = paths.prefix(AppLayout.treeConflictRestoreListedPathLimit)
        var lines = [title]
        lines += listed.map { "  " + $0.precomposedStringWithCanonicalMapping }
        if paths.count > listed.count {
            lines.append("  " + appLanguage.localized(
                .ui.conflict.more,
                String(paths.count - listed.count)
            ))
        }
        return lines
    }
}

extension View {
    func revertConfirmation() -> some View { modifier(RevertConfirmationModifier()) }
}
