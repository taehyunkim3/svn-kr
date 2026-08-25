import Foundation
import Testing
@testable import SVNMac

@Test func recoveryStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.working.copy.cleanup.completed.11c93f4a",
        "ui.working.copy.cleanup.failed.contact.support.81a7d2ce",
        "ui.checkout.recovery.validation.failed.5fd4218c",
        "ui.canceled.checkout.folder.emptied.b08f7c21",
        "ui.canceled.checkout.folder.not.emptied.9ea1354b",
        "ui.working.copy.operation.interrupted.run.cleanup.0bc374e1",
        "ui.file.remains.in.conflict.resolve.before.retry.4d17ac82",
        "ui.lock.belongs.to.another.working.copy.force.unlock.27e93bd0",
        "ui.the.lock.was.force.released.16b02da9",
        "ui.release.lock.normally.5e1039ab",
        "ui.try.normal.unlock.before.force.unlock.8a21f763",
        "ui.force.release.repository.lock.31d7f2c4",
        "ui.force.release.lock.a4ef2d91",
        "ui.not.available.60326cf1",
        "ui.force.unlock.details.owner.time.comment.original.93c28fb0",
        "ui.working.copy.cleanup.62f3ac11",
        "ui.operation.was.interrupted.cleanup.prompt.c7f01d92",
        "ui.run.working.copy.cleanup.b71c28de",
        "ui.cleaning.working.copy.2a9ed647",
        "ui.cleanup.interrupted.working.copy.manually.46d93c1e",
        "ui.checkout.was.interrupted.9d8a23c0",
        "ui.incomplete.checkout.recovery.options.f31ea907",
        "ui.empty.checkout.folder.7a1c8e53",
        "ui.continue.checkout.84b37ce1",
        "ui.cleaning.and.continuing.checkout.18fa2d6b",
        "ui.empty.canceled.checkout.folder.confirmation.6e12c9ad",
        "ui.empty.folder.destructive.30d295e8",
        "ui.only.verified.working.copy.will.be.deleted.path.d8c0a71e",
        "ui.checkout.folder.was.not.empty.cannot.delete.0e6d49b2",
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
