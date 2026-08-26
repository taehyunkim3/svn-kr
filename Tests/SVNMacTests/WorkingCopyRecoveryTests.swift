import Foundation
import Testing
@testable import SVNMac

@Test func recoveryStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.cleanup.workingCopyCleanupCompleted",
        "ui.cleanup.workingCopyCleanupFailedDoNotRetryCleanupRepeatedlyCopy",
        "ui.recovery.interruptedCheckoutFolderNoLongerValidSvnWorkingCopySo",
        "ui.recovery.emptiedInterruptedCheckoutFolder",
        "ui.recovery.folderNotEmptiedBecauseItCouldNotVerifiedSafelyInterrupted",
        "ui.error.workingCopyOperationInterruptedRunWorkingCopyCleanupTryOperation",
        "ui.error.fileRemainsConflictGoChangesChooseResolveConflictsResolveIt",
        "ui.error.lockTokenDoesNotBelongCurrentWorkingCopyReviewOwner",
        "ui.lock.repositoryLockForceReleased",
        "ui.lock.releaseFromListAction",
        "ui.lock.tryNormalUnlockFirstIfWorkingCopyNoMatchingLock",
        "ui.lock.forceReleaseRepositoryLock",
        "ui.lock.forceReleaseLock",
        "ui.lock.notAvailable",
        "ui.lock.forceReleasingCanInterruptSomeoneElseWorkPathOwnerLocked",
        "ui.cleanup.workingCopyCleanup",
        "ui.cleanup.operationInterruptedLikeCleanUpWorkingCopyTryAgainCleanup",
        "ui.cleanup.runCleanup",
        "ui.cleanup.cleaningWorkingCopy",
        "ui.cleanup.manuallyCleanUpInterruptedLockedSvnWorkingCopy",
        "ui.recovery.checkoutInterrupted",
        "ui.recovery.folderIncompleteSvnWorkingCopyContinueRegisteringItCleaningIt",
        "ui.recovery.emptyFolderRequestAction",
        "ui.recovery.continueCheckout",
        "ui.recovery.cleaningContinuing",
        "ui.recovery.emptyInterruptedCheckoutFolder",
        "ui.recovery.emptyFolderConfirmationAction",
        "ui.recovery.allContentsVerifiedInterruptedSvnWorkingCopyFolderBelowDeleted",
        "ui.recovery.folderAlreadyFilesBeforeCheckoutSoAppNotEmptyIt",
        "ui.recovery.recoveryFolderMustBeOutsideCurrentWorkingFolder",
    ]
    let resources = try svnMacSources().appendingPathComponent("Resources", isDirectory: true)
    let files = [
        resources.appendingPathComponent("Localizable.xcstrings"),
        resources.appendingPathComponent("ko.lproj/Localizable.strings"),
        resources.appendingPathComponent("en.lproj/Localizable.strings"),
    ]

    for file in files {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for key in keys {
            #expect(contents.contains(key), "\(key) is missing from \(file.path)")
        }
    }
}

@Test func lockAndCheckoutRecoveryViewsExposeRequiredActionsWithoutUsernameGate() throws {
    let sources = try svnMacSources()
    let locks = try source(named: "RepositoryLocksView.swift", in: sources)
    let repositoryDialogs = try source(named: "RepositoryDialogs.swift", in: sources)
    let recoveryDialogs = try source(named: "WorkingCopyRecoveryDialogs.swift", in: sources)

    #expect(!locks.contains("lock.owner == store.selectedProject?.username"))
    #expect(locks.contains("Task { await store.unlock(lock) }"))
    #expect(locks.contains("Task { await store.forceUnlock(request) }"))
    #expect(repositoryDialogs.contains("store.requestSelectedWorkingCopyCleanup()"))
    #expect(recoveryDialogs.contains("store.resumeCanceledCheckout(request)"))
    #expect(recoveryDialogs.contains("store.emptyCanceledCheckout(request)"))
    #expect(recoveryDialogs.contains("role: .destructive"))
}

@Test func folderEmptyingRequiresRealMetadataAndRejectsSymlinkRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("checkout-emptying-\(UUID().uuidString)", isDirectory: true)
    let workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
    let metadata = workingCopy.appendingPathComponent(".svn", isDirectory: true)
    let symlink = root.appendingPathComponent("working-copy-link", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
    try Data("sqlite".utf8).write(to: metadata.appendingPathComponent("wc.db"))
    try Data("partial".utf8).write(to: workingCopy.appendingPathComponent("partial.txt"))
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: workingCopy)
    let manager = FileManagerWorkingCopyRecoveryFileManager()

    #expect(throws: WorkingCopyRecoveryFileError.self) {
        try manager.emptyWorkingCopy(at: symlink.path)
    }
    #expect(FileManager.default.fileExists(atPath: workingCopy.appendingPathComponent("partial.txt").path))

    try manager.emptyWorkingCopy(at: workingCopy.path)
    #expect(try FileManager.default.contentsOfDirectory(atPath: workingCopy.path).isEmpty)
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
