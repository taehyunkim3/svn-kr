import Foundation
import Testing
@testable import SVNMac

@Test func fileHistoryWiresSafeSaveBeforeDestructiveRestoreWithProgress() throws {
    let sources = try revisionRestoreSources()
    let view = try String(
        contentsOf: sources.appendingPathComponent("FileHistoryView.swift"),
        encoding: .utf8
    )
    let saveKey = ".ui.save.thisRevisionAs"
    let restoreKey = ".ui.restore.workingFileToRevision"

    let savePosition = try #require(view.range(of: saveKey)?.lowerBound)
    let restorePosition = try #require(view.range(of: restoreKey)?.lowerBound)
    #expect(savePosition < restorePosition)
    #expect(view.contains("ActionProgressLabel("))
    #expect(view.contains("store.requestHistoryRevisionRestore("))
    #expect(view.contains("role: .destructive"))
    #expect(view.contains("store.confirmHistoryRevisionRestore(request)"))
    #expect(view.contains("store.isHistoryRevisionOperationRunning"))
}

@Test func commitHistorySelectedFileWiresTheExistingRevisionActions() throws {
    let sources = try revisionRestoreSources()
    let view = try String(
        contentsOf: sources.appendingPathComponent("HistoryRevisionDiffView.swift"),
        encoding: .utf8
    )

    #expect(view.contains("HistoryRevisionActions("))
    #expect(view.contains("store.prepareHistoryRevisionActions("))
    #expect(view.contains(".historyRevisionRestoreConfirmation()"))
}

@Test func revisionSaveUsesSecurityScopedDestinationAccess() throws {
    let sources = try revisionRestoreSources()
    let historyStore = try String(
        contentsOf: sources.appendingPathComponent("ProjectStore+History.swift"),
        encoding: .utf8
    )

    #expect(historyStore.contains("request.destinationURL.startAccessingSecurityScopedResource()"))
    #expect(historyStore.contains("request.destinationURL.stopAccessingSecurityScopedResource()"))
}

@Test func revisionHistoryUsesOnlyTheClientInjectedIntoProjectStore() throws {
    let sources = try revisionRestoreSources()
    let dependencies = try String(
        contentsOf: sources.appendingPathComponent("ProjectDependencies.swift"),
        encoding: .utf8
    )
    let historyStore = try String(
        contentsOf: sources.appendingPathComponent("ProjectStore+History.swift"),
        encoding: .utf8
    )
    let recoveryState = try String(
        contentsOf: sources.appendingPathComponent("ProjectRecoveryState.swift"),
        encoding: .utf8
    )
    let service = try String(
        contentsOf: sources.appendingPathComponent("RevisionFileService.swift"),
        encoding: .utf8
    )

    #expect(dependencies.contains("func fileContents("))
    #expect(dependencies.contains("func export("))
    #expect(historyStore.contains("using: client"))
    #expect(historyStore.contains("try await client.fileContents("))
    #expect(!historyStore.contains("as? any"))
    #expect(!recoveryState.contains("historyRevisionClient"))
    #expect(service.contains("using client: any SVNClientServing"))
    #expect(!service.contains("HistoryRevisionClient"))
    #expect(!service.contains("LiveHistoryRevisionClient"))
}

@Test func revisionRestoreStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.save.this.revision.as.3e8d79a1",
        "ui.saving.revision.4fb2c8d0",
        "ui.restore.working.file.to.revision.79c4a2e6",
        "ui.restoring.revision.c840d51f",
        "ui.restore.working.file.confirmation.0ab7e3c9",
        "ui.restore.working.file.warning.62d159af",
        "ui.restored.revision.commit.required.f9346b20",
        "ui.saved.historical.revision.76ec18b4",
        "ui.revision.restore.missing.working.file.346db8a7",
        "ui.revision.restore.unsafe.working.file.4a960fb3",
        "ui.revision.restore.path.outside.working.copy.87d5e210",
        "ui.revision.restore.backup.inside.working.copy.107e9c6a",
        "ui.revision.restore.backup.verification.failed.d9152a6c",
        "ui.revision.restore.replacement.verification.failed.b8714e35",
        "ui.revision.save.invalid.destination.5f4d2c81",
        "ui.revision.history.client.unavailable.5d7a91c2",
    ]
    let resources = try revisionRestoreSources().appendingPathComponent("Resources", isDirectory: true)
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
        AppLanguage.english.localized(.ui.restored.revisionCommitRequired, "report.xlsx", "17")
            == "Restored report.xlsx to r17. This is now a local change. Commit it to update the server."
    )
}

private func revisionRestoreSources() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
