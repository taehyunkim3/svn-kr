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
