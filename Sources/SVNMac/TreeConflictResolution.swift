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

/// 트리 충돌 해결 시트가 사용하는 세션입니다.
struct TreeConflictSession: Identifiable, Hashable {
    let id: UUID
    let details: SVNConflictDetails
    let requestedPath: String
    let versionedPath: String
    let wasCanonicallyResolved: Bool

    init(
        id: UUID = UUID(),
        details: SVNConflictDetails,
        requestedPath: String,
        versionedPath: String,
        wasCanonicallyResolved: Bool
    ) {
        self.id = id
        self.details = details
        self.requestedPath = requestedPath
        self.versionedPath = versionedPath
        self.wasCanonicallyResolved = wasCanonicallyResolved
    }
}
