import Foundation
import SVNCore

struct ProjectChangesState {
    var statuses: [SVNStatusEntry] = []
    var pathCollisions: [SVNPathCollision] = []
    var ignoredStatuses: [SVNStatusEntry] = []
    var ignoreRules: [SVNIgnoreRule] = []
    var gitIgnoreImportItems: [IgnoreImportItem] = []
    var selectedGitIgnoreImportIDs: Set<IgnoreImportItem.ID> = []
    var hasComparedGitIgnore = false
    var gitIgnoreFileExists = false
    var gitIgnoreLastComparedAt: Date?
    var showsIgnoredFiles = false
    var selectedPaths: Set<String> = []
    var selectedStatusPath: String?
    var diffContent: DiffContent = .placeholder
}

struct ProjectBrowserState {
    var repositoryLocks: [SVNLockInfo] = []
    var workingCopyFileTree: [WorkingCopyFileNode] = []
}

struct ProjectHistoryState {
    var logs: [SVNLogEntry] = []
    var selectedHistoryRevision: String?
    var selectedHistoryPath: String?
    var historyDiffContent: DiffContent = .placeholder
    var hasMoreHistory = true
    var workingCopyRevision: SVNWorkingCopyRevision?
    var workingCopyRepositoryPath: String?
    var isWorkingCopyOutOfDate: Bool?
    var fileHistory: [SVNLogEntry] = []
    var fileHistoryPath: String?
}

struct ProjectUpdateState {
    var remoteChanges: [SVNStatusEntry] = []
}
