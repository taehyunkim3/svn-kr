import Foundation
import Testing
@testable import SVNMac

@Test func sharedPresentationStateHasOneActiveOwner() throws {
    let sources = try svnMacSourceText()

    #expect(occurrences(of: ".sheet(isPresented: $store.isShowingFileHistory)", in: sources) == 1)
    #expect(occurrences(of: ".sheet(item: $store.recoveryState.versionedFileActionRequest)", in: sources) == 1)
    #expect(occurrences(of: ".documentOpenConfirmation()", in: sources) == 1)
    #expect(occurrences(of: ".explicitLockConfirmation()", in: sources) == 1)
    #expect(occurrences(of: ".historyRevisionRestoreConfirmation()", in: sources) == 1)

    let restoreConfirmation = try source("CommitDeletionRestoreConfirmation.swift")
    let commitConfirmation = try source("CommitConfirmationView.swift")
    #expect(restoreConfirmation.contains("commitDeletionRestorePresentationOwner"))
    #expect(commitConfirmation.contains("commitDeletionRestorePresentationOwner"))
}

@Test func everyContextualErrorSheetSuppressesTheRootPresenter() throws {
    let projectStore = try source("ProjectStore.swift")
    let ownerStart = try #require(projectStore.range(of: "var hasContextualErrorPresentationOwner: Bool"))
    let ownerTail = projectStore[ownerStart.lowerBound...]
    let ownerEnd = try #require(ownerTail.range(of: "\n    var visibleStatuses"))
    let owner = ownerTail[..<ownerEnd.lowerBound]

    #expect(owner.contains("recoveryState.propertyConflictSession != nil"))
}

@Test func mutatingSheetOperationsCannotBeDismissedAsIfCanceled() throws {
    let content = try source("ContentView.swift")
    let projectStore = try source("ProjectStore.swift")
    let update = try source("UpdatePreviewView.swift")

    #expect(update.contains(".interactiveDismissDisabled(store.isUpdatingSelectedProject)"))
    #expect(update.contains(".disabled(store.isUpdatingSelectedProject)"))
    #expect(content.contains(".interactiveDismissDisabled(store.isCleaningSelectedProjectTemporaryFiles)"))
    #expect(projectStore.contains("if !isShowingPathRecovery, isPathRecoveryRunning"))
}

private func svnMacSourceText() throws -> String {
    try FileManager.default.contentsOfDirectory(
        at: svnMacSources(),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "swift" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { try String(contentsOf: $0, encoding: .utf8) }
    .joined(separator: "\n")
}

private func source(_ fileName: String) throws -> String {
    try String(
        contentsOf: svnMacSources().appendingPathComponent(fileName),
        encoding: .utf8
    )
}

private func occurrences(of needle: String, in value: String) -> Int {
    value.components(separatedBy: needle).count - 1
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
