import Foundation

/// 충돌 해결과 작업 복사본 복구 화면이 쓰는 프로젝트별 상태입니다.
/// `ProjectStore`는 이 구조체 하나만 저장 프로퍼티로 들고 있으므로,
/// 새 화면 상태가 필요하면 `ProjectStore.swift`를 고치지 말고 여기에 필드를 추가합니다.
struct ProjectRecoveryState {
    var commitConfirmationRequest: CommitConfirmationRequest?
    var selectedCommitDeletionRestorePaths: Set<String> = []
    var commitDeletionRestoreRequest: CommitDeletionRestoreRequest?
    var commitDeletionRestoreFailureMessage: String?
    var propertyConflictSession: PropertyConflictSession?
    var updatePreview = UpdatePreviewState()
    var outOfDateCommitRecoveryRequest: OutOfDateCommitRecoveryRequest?
    var repositoryURL: String?
    var repositoryRelocationRequest: RepositoryRelocationRequest?
    var repositoryRelocationFailureMessage: String?
    var versionedFileActionRequest: VersionedFileActionRequest?
    var versionedFileActionFailureMessage: String?
    var needsLockPaths: Set<String> = []
    var explicitLockRequest: ExplicitLockRequest?
    var bulkUnlockRequest: BulkUnlockRequest?
    var bulkUnlockResult: BulkUnlockResult?
    var fileHistoryRequest: FileHistoryRequest?
    var historyRevisionRestoreRequest: HistoryRevisionRestoreRequest?
    var historyRevisionOperation: HistoryRevisionOperation?
    var repositoryBrowseSelectedURL: String?
    var commitSubmissionID: UUID?
    var projectRegistrationSessionID: UUID?

    mutating func beginCommitSubmission(isActionBlocked: Bool, canCommit: Bool) -> UUID? {
        guard commitSubmissionID == nil, !isActionBlocked, canCommit else { return nil }
        let id = UUID()
        commitSubmissionID = id
        return id
    }

    mutating func endCommitSubmission(_ id: UUID) {
        guard commitSubmissionID == id else { return }
        commitSubmissionID = nil
    }
}
