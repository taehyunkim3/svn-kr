import Foundation
import SVNCore

struct UpdatePreviewState {
    static let maximumVisibleCommitCount = 100

    private(set) var commits: [SVNLogEntry] = []
    private(set) var totalCommitCount = 0
    private(set) var errorMessages: [String] = []
    private(set) var expandedRevisions: Set<String> = []

    var errorMessage: String? {
        guard !errorMessages.isEmpty else { return nil }
        return errorMessages.joined(separator: "\n\n")
    }

    var isTruncated: Bool {
        totalCommitCount > commits.count
    }

    mutating func beginLoading() {
        self = UpdatePreviewState()
    }

    mutating func receive(_ incomingCommits: [SVNLogEntry]) {
        totalCommitCount = incomingCommits.count
        commits = Array(incomingCommits.prefix(Self.maximumVisibleCommitCount))
        expandedRevisions.formIntersection(commits.map(\.revision))
    }

    mutating func recordFailure(_ message: String) {
        guard !errorMessages.contains(message) else { return }
        errorMessages.append(message)
    }

    func isExpanded(_ revision: String) -> Bool {
        expandedRevisions.contains(revision)
    }

    mutating func setExpanded(_ isExpanded: Bool, revision: String) {
        if isExpanded {
            expandedRevisions.insert(revision)
        } else {
            expandedRevisions.remove(revision)
        }
    }

    func canRunUpdate(hasRemoteChanges: Bool, isWorkingCopyOutOfDate: Bool) -> Bool {
        !commits.isEmpty || hasRemoteChanges || isWorkingCopyOutOfDate || errorMessage != nil
    }
}

/// 서버가 커밋을 out-of-date로 거절했으면 미리보기가 비어 있어도 업데이트를 실행할 수 있어야 합니다.
/// 거절 사실 자체가 작업 복사본이 뒤처졌다는 서버의 최종 판정입니다.
enum UpdatePreviewCommitRecoveryPolicy {
    static func treatsWorkingCopyAsOutOfDate(
        hasCommitRecovery: Bool,
        isWorkingCopyOutOfDate: Bool?
    ) -> Bool {
        hasCommitRecovery || isWorkingCopyOutOfDate == true
    }
}

