import Foundation
import Observation
import SVNCore

@Observable
final class ProjectChangesStore {
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
    var expandedUntrackedDirectoryPaths: Set<String> = []
    var untrackedChildrenByDirectory: [String: [SVNUntrackedChild]] = [:]
    var loadingUntrackedDirectoryPaths: Set<String> = []
    var untrackedChildrenErrorsByDirectory: [String: String] = [:]
    var selectedUntrackedChildPaths: Set<String> = []
    var untrackedChildrenRefreshGeneration = 0
    var selectedStatusPath: String?
    var diffContent: DiffContent = .placeholder
}

struct VisibleUntrackedChild: Identifiable, Hashable {
    let child: SVNUntrackedChild
    let parentDirectory: String
    let depth: Int

    var id: SVNPathIdentity { child.id }
}

@Observable
final class ProjectBrowserStore {
    var repositoryLocks: [SVNLockInfo] = []
    var treeState = WorkingCopyBrowserTreeState()
    var svnEntries: [SVNWorkingCopyEntry] = []
    var refreshGeneration = 0
}

@Observable
final class ProjectHistoryStore {
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

@Observable
final class ProjectUpdateStore {
    var remoteChanges: [SVNStatusEntry] = []
    var cleansRepositoryTemporaryFilesAfterUpdate = false
    var temporaryFileCleanupAssessments: [TemporaryFileCleanupAssessment] = []
    var selectedTemporaryFileCleanupPaths: Set<String> = []
    var temporaryFileCleanupFailures: [TemporaryFileCleanupFailure] = []
}

struct TemporaryFileCleanupFailure: Identifiable, Hashable {
    let path: String
    let reason: String

    var id: String { "operation-failure:\(path)" }
}
