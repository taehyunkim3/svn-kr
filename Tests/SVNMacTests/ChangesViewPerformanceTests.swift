import Foundation
import Testing

@Suite("ChangesViewPerformanceTests")
struct ChangesViewPerformanceTests {
    @Test func commitMessageStateIsOwnedByIsolatedControlsView() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("CommitControlsView()"))
        #expect(!changesView.contains("@State private var commitMessage"))
        #expect(commitControls.contains("@State private var commitMessage"))
    }

    @Test func commitProgressVisibilityUsesStorePolicy() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains("if store.showsCommitProgressLog"))
        #expect(!changesView.contains("isCommitInteractionLocked || !store.commitLog.isEmpty"))
    }

    @Test func changedFileListDoesNotConcatenateStatusCollections() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(!changesView.contains("store.statuses +"))
        #expect(changesView.contains("let visibleStatuses = store.visibleStatuses"))
        #expect(changesView.contains("let visibleIgnoredStatuses = store.visibleIgnoredStatuses"))
        #expect(changesView.contains("ForEach(visibleStatuses)"))
        #expect(changesView.contains("ForEach(visibleIgnoredStatuses)"))
    }

    @Test func largeHistoryDiffUsesOneAttributedTextView() throws {
        let sources = try svnMacSources()
        let historyDiff = try source(named: "HistoryRevisionDiffView.swift", in: sources)
        let diffText = try source(named: "DiffTextView.swift", in: sources)

        #expect(historyDiff.contains("DiffTextView(value)"))
        #expect(!historyDiff.contains("ForEach(Array(lines.enumerated())"))
        #expect(diffText.contains("Text(text)"))
    }

    @Test func changesViewDistinguishesMissingStatesAndSummarizesUnicodeCollisions() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(!changesView.contains(".ui.recovery.locallyMissingActionRequired"))
        #expect(changesView.contains(".ui.cleanup.needed"))
        #expect(changesView.contains(".ui.changes.unicodePathConflict"))
        #expect(changesView.contains("entry.isSelectableForCommit"))
        #expect(changesView.contains("entry.canScheduleRepositoryDeletion"))
        #expect(changesView.contains("case .missing: appLanguage.localized(.ui.changes.pendingDeletionStatus)"))
        #expect(changesView.contains(".ui.changes.deleteRepository"))
        #expect(changesView.contains(".ui.changes.restorePendingDeletions"))
        #expect(changesView.contains("store.requestSelectedDeletionRestore()"))
        #expect(commitControls.contains("store.selectAllCommitPaths()"))
        #expect(commitControls.contains("store.canCommitSelectedPaths"))
        #expect(commitControls.contains("store.scheduledDeletionCount"))
    }

    @Test func unversionedDirectoryExplainsRecursiveCommit() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains(".ui.changes.filesInsideFolderAddedTogether"))
        #expect(changesView.contains("entry.item == .unversioned && entry.nodeKind == .directory"))
    }

    @Test func untrackedChildCheckboxUsesExistingCommitInteractionLock() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains("untrackedChildRow"))
        #expect(changesView.contains("|| store.isUntrackedChildSelectionDisabled(in: row.parentDirectory)"))
        #expect(changesView.contains(".disabled(store.isCommitInteractionLocked ||"))
    }

    @Test func temporaryFilesHaveDedicatedBadgeAndSelectAllPolicy() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("TemporaryFilePolicy.isTemporaryFile(entry)"))
        #expect(changesView.contains(".ui.changes.temporary"))
        #expect(commitControls.contains("store.selectAllCommitPaths()"))
        #expect(commitControls.contains("store.clearCommitSelection()"))
    }

    @Test func hiddenTemporaryFilesDoNotLeakIntoHistoryOrBulkDeletion() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let historyView = try source(named: "HistoryView.swift", in: sources)

        #expect(changesView.contains("store.visibleStatuses.filter(\\.canScheduleRepositoryDeletion)"))
        #expect(!historyView.contains("store.statuses.isEmpty"))
        #expect(historyView.contains("store.visibleStatuses.isEmpty"))
    }

    @Test func collisionActionsUseAggregateRepairabilityAndManualServerGuidance() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains(".ui.cleanup.cleanUpEquivalentPath"))
        #expect(changesView.contains("store.canRepairCanonicalAliases"))
        #expect(changesView.contains("await store.repairCanonicalAliases()"))
        #expect(changesView.contains(".ui.changes.resolveDuplicateServerPathsManually"))
        #expect(!changesView.contains("if collision.repairableRawPath != nil"))
        #expect(!changesView.contains("await store.beginPathRecovery()"))
    }

    @Test func conflictResolutionOffersThreeSafeBinaryChoicesAndPathNotice() throws {
        let view = try source(named: "ConflictResolutionView.swift", in: try svnMacSources())

        #expect(view.contains(".ui.conflict.openMyFile"))
        #expect(view.contains(".ui.conflict.openServerFile"))
        #expect(view.contains(".ui.conflict.useMineAction"))
        #expect(view.contains(".ui.conflict.useServerAction"))
        #expect(view.contains(".ui.conflict.useWorkingFileAction"))
        #expect(view.contains("pendingChoice = .working"))
        #expect(view.contains("session.wasCanonicallyResolved"))
        #expect(view.contains(".ui.conflict.macosUnicodePathMatchedActualSvnManagedPath"))
        #expect(view.contains(".ui.conflict.openBackupFolder"))
        #expect(view.contains("session.details.path"))
        #expect(view.contains(".ui.conflict.whenChooseVersionCurrentWorkingFilePreservedSeparatelyHiddenRecovery"))
        #expect(view.contains("interactiveDismissDisabled(store.isResolvingConflict)"))
        #expect(view.contains("store.isResolvingConflict"))
        #expect(view.contains(".ui.common.cancel"))
        #expect(view.components(separatedBy: ".disabled(store.isResolvingConflict)").count - 1 == 5)
        #expect(!view.contains(".ui.common.close"))
        #expect(view.contains(".ui.conflict.bothVersionsCopiedBackupFolderEditingCopiesDoesNotChange"))
        #expect(!view.contains("enum ConflictResolutionCopy"))
        #expect(!view.contains("두 버전 모두 원본 옆에 보관"))
        #expect(!view.contains("현재 파일로 충돌 해결 완료"))
    }

    private func svnMacSources() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    }

    private func source(named name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
