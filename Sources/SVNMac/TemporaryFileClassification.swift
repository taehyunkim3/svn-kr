import Foundation
import SVNCore

/// 임시파일의 표시와 커밋 포함 규칙을 한곳에서 결정합니다.
enum TemporaryFilePolicy {
    /// 이름상 임시파일인지 판정합니다. 버전관리 항목과 종류 미상 항목도 배지로
    /// 구분하되, 디렉터리는 파일 패턴과 이름이 같아도 임시파일로 보지 않습니다.
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

    /// 목록과 커밋 대상에서 숨길 수 있는 항목은 기존 정책대로 확인된 미버전 파일로 제한합니다.
    static func isHideableTemporaryFile(_ entry: SVNStatusEntry) -> Bool {
        entry.item == .unversioned
            && entry.nodeKind == .file
            && isTemporaryFile(entry)
    }

    static func visibleEntries(
        _ entries: [SVNStatusEntry],
        hideTemporaryFiles: Bool
    ) -> [SVNStatusEntry] {
        guard hideTemporaryFiles else { return entries }
        return entries.filter { !isHideableTemporaryFile($0) }
    }

    static func commitEligibleEntries(
        _ entries: [SVNStatusEntry],
        hideTemporaryFiles: Bool
    ) -> [SVNStatusEntry] {
        visibleEntries(entries, hideTemporaryFiles: hideTemporaryFiles)
            .filter(\.isSelectableForCommit)
    }

    static func automaticallySelectedEntries(_ entries: [SVNStatusEntry]) -> [SVNStatusEntry] {
        entries.filter { $0.isSelectableForCommit && !isHideableTemporaryFile($0) }
    }
}
