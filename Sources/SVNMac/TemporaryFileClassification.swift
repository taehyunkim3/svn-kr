import Foundation
import SVNCore

/// 변경 목록에는 유지하되 자동 전체 선택에서는 제외할 수 있는 임시 파일을 판정합니다.
extension SVNStatusEntry {
    var isTemporaryFile: Bool {
        guard item == .unversioned, nodeKind == .file else { return false }

        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("~$")
            || name == ".DS_Store"
            || name.hasPrefix("._")
            || name.hasSuffix(".swp")
            || name.hasSuffix(".swo")
            || name.hasSuffix("~")
            || (name.hasPrefix("#") && name.hasSuffix("#"))
            || name.hasPrefix(".#")
    }
}
