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

        #expect(!changesView.contains(".ui.locally.missingActionRequired"))
        #expect(changesView.contains(".ui.cleanup.needed"))
        #expect(changesView.contains(".ui.unicode.pathConflict"))
        #expect(changesView.contains("entry.isSelectableForCommit"))
        #expect(changesView.contains("entry.canScheduleRepositoryDeletion"))
        #expect(changesView.contains("case .missing: appLanguage.localized(.ui.pending.deletionPrimary)"))
        #expect(changesView.contains(".ui.delete.fromRepository"))
        #expect(changesView.contains(".ui.restore.selectedPendingDeletions"))
        #expect(changesView.contains("store.requestSelectedDeletionRestore()"))
        #expect(commitControls.contains("store.selectAllStatusPaths"))
        #expect(commitControls.contains("store.canCommitSelectedPaths"))
        #expect(commitControls.contains("store.scheduledDeletionCount"))
    }

    @Test func unversionedDirectoryExplainsRecursiveCommit() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains(".ui.files.insideThisFolderWillBeAddedTogether"))
        #expect(changesView.contains("entry.item == .unversioned && entry.nodeKind == .directory"))
    }

    @Test func temporaryFilesHaveDedicatedBadgeAndSelectAllPolicy() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("TemporaryFilePolicy.isTemporaryFile(entry)"))
        #expect(changesView.contains(".ui.temporary.label"))
        #expect(commitControls.contains("store.selectAllStatusPaths"))
        #expect(commitControls.contains("store.selectedPaths.removeAll()"))
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

        #expect(changesView.contains(".ui.clean.upEquivalentPath"))
        #expect(changesView.contains("store.canRepairCanonicalAliases"))
        #expect(changesView.contains("await store.repairCanonicalAliases()"))
        #expect(changesView.contains(".ui.resolve.duplicateServerPathsManually"))
        #expect(!changesView.contains("if collision.repairableRawPath != nil"))
        #expect(!changesView.contains("await store.beginPathRecovery()"))
    }

    @Test func conflictResolutionOffersThreeSafeBinaryChoicesAndPathNotice() throws {
        let view = try source(named: "ConflictResolutionView.swift", in: try svnMacSources())

        #expect(view.contains(".ui.localizationOpen.myFile"))
        #expect(view.contains(".ui.localizationOpen.serverFile"))
        #expect(view.contains(".ui.use.myFilePrimary"))
        #expect(view.contains(".ui.use.serverFilePrimary"))
        #expect(view.contains(".ui.use.currentWorkingFilePrimary"))
        #expect(view.contains("pendingChoice = .working"))
        #expect(view.contains("session.wasCanonicallyResolved"))
        #expect(view.contains(".ui.the.macosUnicodePathWasMatchedToTheActual"))
        #expect(view.contains(".ui.localizationOpen.backupFolder"))
        #expect(view.contains("session.details.path"))
        #expect(view.contains(".ui.when.youChooseAVersionTheCurrentWorkingFi"))
        #expect(view.contains("interactiveDismissDisabled(store.isResolvingConflict)"))
        #expect(view.contains("store.isResolvingConflict"))
        #expect(view.contains(".ui.cancel.label"))
        #expect(view.components(separatedBy: ".disabled(store.isResolvingConflict)").count - 1 == 5)
        #expect(!view.contains(".ui.close.label"))
        #expect(view.contains(".ui.both.versionsWereCopiedToABackupFolderEdi"))
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
