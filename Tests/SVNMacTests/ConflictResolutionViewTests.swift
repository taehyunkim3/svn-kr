import Foundation
import Testing
@testable import SVNMac

@Test func contentConflictHidesWorkingChoiceForBinaryFiles() throws {
    let sources = try svnMacSources()
    let conflictResolution = try source(named: "ConflictResolutionView.swift", in: sources)

    #expect(conflictResolution.contains("if !session.isBinary"))
    #expect(conflictResolution.contains("pendingChoice = .working"))
}

@Test func textConflictKeepsWorkingChoiceInACollapsedDisclosure() throws {
    let sources = try svnMacSources()
    let conflictResolution = try source(named: "ConflictResolutionView.swift", in: sources)

    #expect(conflictResolution.contains("@State private var isWorkingFileExpanded = false"))
    #expect(conflictResolution.contains("DisclosureGroup(isExpanded: $isWorkingFileExpanded)"))
    #expect(conflictResolution.contains(".ui.conflict.confirmManuallyEditedContent"))
}

@Test func contentConflictShowsLossWarningsInsideSideBySidePrimaryChoices() throws {
    let sources = try svnMacSources()
    let conflictResolution = try source(named: "ConflictResolutionView.swift", in: sources)

    #expect(conflictResolution.contains("HStack(alignment: .top, spacing: 14)"))
    #expect(conflictResolution.contains("choice: .theirsFull"))
    #expect(conflictResolution.contains("choice: .mineFull"))
    #expect(conflictResolution.contains("systemImage: \"exclamationmark.triangle.fill\""))
    #expect(conflictResolution.contains(".foregroundStyle(.orange)"))
    #expect(conflictResolution.contains(".ui.conflict.overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile"))
}

@Test func treeConflictOffersTwoDestructivelyConfirmedChoices() throws {
    let sources = try svnMacSources()
    let treeConflictResolution = try source(named: "TreeConflictResolutionView.swift", in: sources)

    #expect(treeConflictResolution.contains("choice: .keepWorkingState"))
    #expect(treeConflictResolution.contains("choice: .restoreServerVersion"))
    #expect(treeConflictResolution.contains("Button(confirmationActionTitle, role: .destructive)"))
    #expect(treeConflictResolution.contains("Task { await store.resolveActiveTreeConflict(using: choice) }"))
    #expect(treeConflictResolution.contains(".ui.conflict.treeConflictConcernsPathStateNotFileContentsNotChoice"))
    #expect(treeConflictResolution.contains(".ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer"))
    #expect(treeConflictResolution.contains(".ui.conflict.uncommittedLocalChangesDiscarded"))
    #expect(treeConflictResolution.contains("systemImage: \"exclamationmark.triangle.fill\""))
    #expect(treeConflictResolution.contains(".foregroundStyle(.orange)"))
    #expect(treeConflictResolution.contains("ActionProgressLabel("))
    #expect(treeConflictResolution.contains(".disabled(store.isResolvingConflict)"))
    #expect(treeConflictResolution.contains(".interactiveDismissDisabled(store.isResolvingConflict)"))
    #expect(treeConflictResolution.contains(".detailedErrorPresenter(errorMessage: $store.errorMessage)"))
}

@Test func changesViewPresentsTheTreeConflictSheet() throws {
    let sources = try svnMacSources()
    let changes = try source(named: "ChangesView.swift", in: sources)

    #expect(changes.contains(".sheet(item: $store.activeConflictSession)"))
    #expect(changes.contains(".sheet(item: $store.activeTreeConflictSession)"))
    #expect(changes.contains("TreeConflictResolutionView()"))
}

@Test func propertyConflictOffersTwoDestructivelyConfirmedChoices() throws {
    let sources = try svnMacSources()
    let view = try source(named: "PropertyConflictResolutionView.swift", in: sources)

    #expect(view.contains("choice: .applyServerProperties"))
    #expect(view.contains("choice: .keepMyProperties"))
    #expect(view.contains("Button(confirmationActionTitle, role: .destructive)"))
    #expect(view.contains("Task { await store.resolveActivePropertyConflict(using: choice) }"))
    #expect(view.contains("systemImage: \"exclamationmark.triangle.fill\""))
    #expect(view.contains(".foregroundStyle(.orange)"))
    #expect(view.contains("AppLayout.conflictResolutionSheetMinimumSize"))
}

@Test func changesViewPresentsPropertyConflictAndRevertActions() throws {
    let sources = try svnMacSources()
    let changes = try source(named: "ChangesView.swift", in: sources)

    #expect(changes.contains(".sheet(item: $store.recoveryState.propertyConflictSession)"))
    #expect(changes.contains("PropertyConflictResolutionView()"))
    #expect(changes.contains("entry.propertyState == .conflicted"))
    #expect(!changes.contains("entry.item != .conflicted && entry.item != .missing"))
    #expect(changes.contains(".ui.changes.propertiesModified"))
    #expect(changes.contains(".ui.conflict.propertyConflict"))
    #expect(changes.contains(".ui.update.localFileBlockingUpdate"))
    #expect(changes.contains(".ui.changes.unversionedLocalFileBlockingServerFileSameNameMoveRename"))
    #expect(changes.contains("store.revealInFinder(entry.path)"))
}

@Test func propertyConflictPreparationKeepsOtherConflictSessionsNil() throws {
    let storeConflicts = try source(named: "ProjectStore+Conflicts.swift", in: try svnMacSources())

    #expect(storeConflicts.contains("case .property:"))
    #expect(storeConflicts.contains("activeConflictSession = nil"))
    #expect(storeConflicts.contains("activeTreeConflictSession = nil"))
    #expect(storeConflicts.contains("recoveryState.propertyConflictSession = session"))
    #expect(storeConflicts.contains("canApplyConflictPreparation(requestID, projectID: projectID)"))
    #expect(storeConflicts.contains("resolvedPath.precomposedStringWithCanonicalMapping"))
}

@Test func treeConflictConfirmationListsDisappearingPathsNotOnlyCounts() throws {
    let view = try source(named: "TreeConflictResolutionView.swift", in: try svnMacSources())

    #expect(view.contains("restoreWarningMessage(store.activeTreeConflictSession?.restoreImpact)"))
    #expect(view.contains("impact.unversionedPaths"))
    #expect(view.contains("impact.uncommittedPaths"))
    #expect(view.contains("AppLayout.treeConflictRestoreListedPathLimit"))
    #expect(view.contains(".ui.conflict.revertingRemovesItemsBelowWorkingFolderTheyCopiedBackupFolder"))
    #expect(view.contains(".ui.conflict.fileThatNotRepository"))
    #expect(view.contains(".ui.conflict.uncommittedChange"))
    #expect(view.contains(".ui.conflict.more"))
}

@Test func contentConflictViewAnnouncesTheAccompanyingPropertyConflict() throws {
    let view = try source(named: "ConflictResolutionView.swift", in: try svnMacSources())

    #expect(view.contains("if session.hasPropertyConflict"))
    #expect(view.contains(".ui.conflict.fileAlsoPropertyConflictChoosingVersionBelowResolvesPropertiesSame"))
    #expect(view.contains(".ui.conflict.conflictedProperties"))
    #expect(view.contains(".ui.conflict.serverPropertyValuesAppliedWell"))
    #expect(view.contains(".ui.conflict.propertyValuesKeptWell"))
}

@Test func propertyConflictResolutionPreservesTheWorkingFileBeforeResolving() throws {
    let storeConflicts = try source(named: "ProjectStore+Conflicts.swift", in: try svnMacSources())
    let resolvePropertyRange = try #require(
        storeConflicts.range(of: "func resolveActivePropertyConflict")
    )
    let body = storeConflicts[resolvePropertyRange.lowerBound...]
    let preserveIndex = try #require(body.range(of: "conflictFileService.preserveSubtree"))
    let resolveIndex = try #require(body.range(of: "client.resolveConflict"))
    #expect(preserveIndex.lowerBound < resolveIndex.lowerBound)
}

@Test func propertyConflictStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.conflict.applyServerProperties",
        "ui.conflict.conflictedProperties",
        "ui.conflict.conflictedPropertyNameCouldNotDetermined",
        "ui.conflict.keepMyProperties",
        "ui.conflict.localPropertyValuesDiscarded",
        "ui.changes.unversionedLocalFileBlockingServerFileSameNameMoveRename",
        "ui.update.localFileBlockingUpdate",
        "ui.conflict.propertyConflict",
        "ui.changes.propertiesModified",
        "ui.changes.revertConflictLocalChanges",
        "ui.conflict.incomingServerPropertyValuesDiscardedWorkingCopy",
    ]
    let resources = try svnMacSources().appendingPathComponent("Resources", isDirectory: true)
    let localizationFiles = [
        resources.appendingPathComponent("Localizable.xcstrings"),
        resources.appendingPathComponent("ko.lproj/Localizable.strings"),
        resources.appendingPathComponent("en.lproj/Localizable.strings"),
    ]

    for file in localizationFiles {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for key in keys {
            #expect(contents.contains(key), "\(key) is missing from \(file.path)")
        }
    }
}

@Test func conflictResolutionStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.conflict.applyServerVersion",
        "ui.conflict.confirmCurrentWorkingCopyState",
        "ui.conflict.confirmManuallyEditedContent",
        "ui.conflict.discardLocalChangeRestoreServerFile",
        "ui.conflict.keepMyChange",
        "ui.conflict.uncommittedLocalChangesDiscarded",
        "ui.conflict.ifDeletedItLocallyDeletionRemainsCommitDeleteItServer",
        "ui.conflict.overwriteMyVersion",
        "ui.conflict.restoreFileServerVersion",
        "ui.conflict.overwritingVersionRemovesIncomingServerChangesWorkingFileServerFile",
        "ui.conflict.treeConflict",
        "ui.conflict.treeConflictConcernsPathStateNotFileContentsNotChoice",
    ]
    let resources = try svnMacSources().appendingPathComponent("Resources", isDirectory: true)
    let localizationFiles = [
        resources.appendingPathComponent("Localizable.xcstrings"),
        resources.appendingPathComponent("ko.lproj/Localizable.strings"),
        resources.appendingPathComponent("en.lproj/Localizable.strings"),
    ]

    for file in localizationFiles {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for key in keys {
            #expect(contents.contains(key), "\(key) is missing from \(file.path)")
        }
    }

    #expect(
        AppLanguage.english.localized(.ui.conflict.keepMyChange) == "Keep My Change"
    )
    #expect(
        AppLanguage.korean.localized(.ui.conflict.keepMyChange) == "내 변경 유지"
    )
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
