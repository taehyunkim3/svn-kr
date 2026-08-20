import Foundation
import SVNCore

/// 임시파일의 표시와 커밋 포함 규칙을 한곳에서 결정합니다.
enum TemporaryFilePolicy {
    static func isTemporaryFile(_ entry: SVNStatusEntry) -> Bool {
        guard entry.nodeKind != .directory else { return false }

        let name = (entry.path as NSString).lastPathComponent
        return name.hasPrefix("~$")
            || name == ".DS_Store"
            || name.hasPrefix("._")
            || name.hasSuffix(".swp")
            || name.hasSuffix(".swo")
            || name.hasSuffix("~")
            || (name.hasPrefix("#") && name.hasSuffix("#"))
            || name.hasPrefix(".#")
    }

    static func visibleEntries(
        _ entries: [SVNStatusEntry],
        hideTemporaryFiles: Bool
    ) -> [SVNStatusEntry] {
        guard hideTemporaryFiles else { return entries }
        return entries.filter { !isTemporaryFile($0) }
    }

    static func commitEligibleEntries(
        _ entries: [SVNStatusEntry],
        hideTemporaryFiles: Bool
    ) -> [SVNStatusEntry] {
        visibleEntries(entries, hideTemporaryFiles: hideTemporaryFiles)
            .filter(\.isSelectableForCommit)
    }

    static func automaticallySelectedEntries(_ entries: [SVNStatusEntry]) -> [SVNStatusEntry] {
        entries.filter { $0.isSelectableForCommit && !isTemporaryFile($0) }
    }
}
