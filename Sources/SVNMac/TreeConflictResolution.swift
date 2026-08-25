import Foundation
import SVNCore

/// 트리 충돌에서 사용자가 고를 수 있는 해결 방식입니다.
/// 트리 충돌은 비교할 두 파일이 존재하지 않으므로 내용 충돌과 선택지가 다릅니다.
enum TreeConflictResolutionChoice: String, Hashable, CaseIterable, Identifiable {
    /// 현재 작업 복사본 상태(예: 로컬에서 삭제한 상태)를 정답으로 확정합니다.
    /// `svn resolve --accept working`
    case keepWorkingState
    /// 로컬 변경을 되돌려 서버 버전 파일을 복구합니다.
    /// `svn revert` 후 `svn update`
    case restoreServerVersion

    var id: String { rawValue }
}

/// "서버 버전으로 파일 복구"가 `svn revert --depth infinity`로 지우게 될 하위 항목 하나입니다.
struct TreeConflictRestoreEntry: Identifiable, Hashable {
    enum Risk: String, Hashable {
        /// 저장소에 없는 파일입니다. 되돌리면 저장소 이력에서도 되살릴 수 없습니다.
        case unversioned
        /// 아직 커밋하지 않은 수정·추가입니다. 편집분이 저장소에 없습니다.
        case uncommittedChange
    }

    let relativePath: String
    let risk: Risk

    var id: String { relativePath }
}

/// 되돌리기 확인창이 개수와 경로를 함께 보여줄 수 있도록 모아 둔 결과입니다.
struct TreeConflictRestoreImpact: Hashable {
    let entries: [TreeConflictRestoreEntry]

    init(entries: [TreeConflictRestoreEntry] = []) {
        self.entries = entries
    }

    var isEmpty: Bool { entries.isEmpty }
    var unversionedPaths: [String] { paths(for: .unversioned) }
    var uncommittedPaths: [String] { paths(for: .uncommittedChange) }

    private func paths(for risk: TreeConflictRestoreEntry.Risk) -> [String] {
        entries.filter { $0.risk == risk }.map(\.relativePath)
    }
}

enum TreeConflictRestoreScan {
    /// 되돌릴 대상 아래에서 사라질 항목을 모읍니다.
    /// `svn status`는 버전관리되지 않은 디렉터리를 항목 하나로만 보고하므로,
    /// 그 안의 파일은 `containedFilePaths`로 펼쳐서 경로를 개별로 세웁니다.
    static func impact(
        target: String,
        statuses: [SVNStatusEntry],
        containedFilePaths: (String) -> [String]
    ) -> TreeConflictRestoreImpact {
        var entries: [TreeConflictRestoreEntry] = []
        var seen: Set<String> = []

        func append(_ path: String, risk: TreeConflictRestoreEntry.Risk) {
            guard seen.insert(path.precomposedStringWithCanonicalMapping).inserted else { return }
            entries.append(TreeConflictRestoreEntry(relativePath: path, risk: risk))
        }

        for entry in statuses where isAtOrBelow(entry.path, target: target) {
            let contained = containedFilePaths(entry.path)
            switch entry.item {
            case .unversioned:
                if contained.isEmpty {
                    append(entry.path, risk: .unversioned)
                } else {
                    for path in contained { append(path, risk: .unversioned) }
                }
            case .modified, .added, .replaced, .conflicted:
                // 디렉터리는 하위 항목이 따로 보고되므로 그 자체를 세지 않습니다.
                guard contained.isEmpty else { continue }
                append(entry.path, risk: .uncommittedChange)
            default:
                continue
            }
        }

        let order: [TreeConflictRestoreEntry.Risk] = [.unversioned, .uncommittedChange]
        let sorted = order.flatMap { risk in
            entries
                .filter { $0.risk == risk }
                .sorted { $0.relativePath < $1.relativePath }
        }
        return TreeConflictRestoreImpact(entries: sorted)
    }

    private static func isAtOrBelow(_ path: String, target: String) -> Bool {
        let candidate = path.precomposedStringWithCanonicalMapping
        let root = target.precomposedStringWithCanonicalMapping
        return candidate == root || candidate.hasPrefix(root + "/")
    }
}

/// 트리 충돌 해결 시트가 사용하는 세션입니다.
struct TreeConflictSession: Identifiable, Hashable {
    let id: UUID
    let details: SVNConflictDetails
    let requestedPath: String
    let versionedPath: String
    let wasCanonicallyResolved: Bool
    /// "서버 버전으로 파일 복구"를 골랐을 때 사라질 하위 항목입니다.
    let restoreImpact: TreeConflictRestoreImpact

    init(
        id: UUID = UUID(),
        details: SVNConflictDetails,
        requestedPath: String,
        versionedPath: String,
        wasCanonicallyResolved: Bool,
        restoreImpact: TreeConflictRestoreImpact = TreeConflictRestoreImpact()
    ) {
        self.id = id
        self.details = details
        self.requestedPath = requestedPath
        self.versionedPath = versionedPath
        self.wasCanonicallyResolved = wasCanonicallyResolved
        self.restoreImpact = restoreImpact
    }
}
