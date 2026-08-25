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
    #expect(conflictResolution.contains("ui.confirm.manually.edited.content.97e30ac4"))
}

@Test func contentConflictShowsLossWarningsInsideSideBySidePrimaryChoices() throws {
    let sources = try svnMacSources()
    let conflictResolution = try source(named: "ConflictResolutionView.swift", in: sources)

    #expect(conflictResolution.contains("HStack(alignment: .top, spacing: 14)"))
    #expect(conflictResolution.contains("choice: .theirsFull"))
    #expect(conflictResolution.contains("choice: .mineFull"))
    #expect(conflictResolution.contains("systemImage: \"exclamationmark.triangle.fill\""))
    #expect(conflictResolution.contains(".foregroundStyle(.orange)"))
    #expect(conflictResolution.contains("ui.server.version.changes.will.be.discarded.4ab613d2"))
}

@Test func treeConflictOffersTwoDestructivelyConfirmedChoices() throws {
    let sources = try svnMacSources()
    let treeConflictResolution = try source(named: "TreeConflictResolutionView.swift", in: sources)

    #expect(treeConflictResolution.contains("choice: .keepWorkingState"))
    #expect(treeConflictResolution.contains("choice: .restoreServerVersion"))
    #expect(treeConflictResolution.contains("Button(confirmationActionTitle, role: .destructive)"))
    #expect(treeConflictResolution.contains("Task { await store.resolveActiveTreeConflict(using: choice) }"))
    #expect(treeConflictResolution.contains("ui.tree.conflict.is.not.a.choice.between.two.files.66dcb7a1"))
    #expect(treeConflictResolution.contains("ui.local.deletion.will.remain.and.a.commit.will.de.837b94a0"))
    #expect(treeConflictResolution.contains("ui.local.changes.will.be.discarded.5e8127cf"))
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
    #expect(changes.contains("ui.property.modified.4c9a78e1"))
    #expect(changes.contains("ui.property.conflict.2fd61b8a"))
    #expect(changes.contains("ui.obstructed.local.file.74a9c2e5"))
    #expect(changes.contains("ui.move.or.rename.the.local.file.then.update.1e3c7a90"))
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
    #expect(view.contains("ui.restore.server.version.removes.these.items.9d41c60b"))
    #expect(view.contains("ui.files.not.in.repository.count.2b7fa508"))
    #expect(view.contains("ui.uncommitted.changes.count.7e3c19d4"))
    #expect(view.contains("ui.and.more.items.count.a5d20f16"))
}

@Test func contentConflictViewAnnouncesTheAccompanyingPropertyConflict() throws {
    let view = try source(named: "ConflictResolutionView.swift", in: try svnMacSources())

    #expect(view.contains("if session.hasPropertyConflict"))
    #expect(view.contains("ui.content.and.property.conflict.together.6f0b83e5"))
    #expect(view.contains("ui.conflicted.properties.849bf370"))
    #expect(view.contains("ui.server.properties.also.applied.3ac57d92"))
    #expect(view.contains("ui.my.properties.also.kept.b81e64af"))
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
        "ui.apply.server.properties.51ad840e",
        "ui.conflicted.properties.849bf370",
        "ui.conflicted.property.name.unavailable.0cc5d784",
        "ui.keep.my.properties.68b12ae4",
        "ui.local.property.values.will.be.discarded.f98a7c20",
        "ui.move.or.rename.the.local.file.then.update.1e3c7a90",
        "ui.obstructed.local.file.74a9c2e5",
        "ui.property.conflict.2fd61b8a",
        "ui.property.modified.4c9a78e1",
        "ui.revert.conflict.discards.local.changes.and.conflict.51b3d907",
        "ui.server.property.values.will.be.discarded.84d6f2c1",
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
        "ui.apply.server.version.61c5a01e",
        "ui.confirm.current.working.copy.state.1c63f80b",
        "ui.confirm.manually.edited.content.97e30ac4",
        "ui.discard.local.change.and.restore.server.file.728e0bf1",
        "ui.keep.my.change.14f3a8c6",
        "ui.local.changes.will.be.discarded.5e8127cf",
        "ui.local.deletion.will.remain.and.a.commit.will.de.837b94a0",
        "ui.overwrite.with.mine.8d42f39b",
        "ui.restore.file.from.server.version.4dd51eb7",
        "ui.server.version.changes.will.be.discarded.4ab613d2",
        "ui.tree.conflict.2ea1184c",
        "ui.tree.conflict.is.not.a.choice.between.two.files.66dcb7a1",
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
        AppLanguage.english.localized("ui.keep.my.change.14f3a8c6") == "Keep My Change"
    )
    #expect(
        AppLanguage.korean.localized("ui.keep.my.change.14f3a8c6") == "내 변경 유지"
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
