import Foundation

struct OutOfDateCommitRecoveryRequest: Identifiable, Equatable {
    let id: UUID
    let projectID: SVNProject.ID
    let message: String
    let paths: [String]
    let details: String
    var conflictedPaths: [String]
    var hasCompletedUpdate: Bool

    init(
        id: UUID = UUID(),
        projectID: SVNProject.ID,
        message: String,
        paths: [String],
        details: String,
        conflictedPaths: [String] = [],
        hasCompletedUpdate: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.message = message
        self.paths = paths
        self.details = details
        self.conflictedPaths = conflictedPaths
        self.hasCompletedUpdate = hasCompletedUpdate
    }
}
