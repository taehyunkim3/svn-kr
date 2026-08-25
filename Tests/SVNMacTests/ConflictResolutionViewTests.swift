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
