import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func propertyConflictChoicesMapToWholePropertyResolutionChoices() {
    #expect(PropertyConflictResolutionChoice.applyServerProperties.svnChoice == .theirsFull)
    #expect(PropertyConflictResolutionChoice.keepMyProperties.svnChoice == .mineFull)
}

@Test func propertyConflictSessionPreservesRequestedAndVersionedPaths() {
    let versionedPath = "공유/문서"
    let requestedPath = versionedPath.decomposedStringWithCanonicalMapping
    let details = SVNConflictDetails(path: versionedPath, type: "property", operation: "update")

    let session = PropertyConflictSession(
        details: details,
        requestedPath: requestedPath,
        versionedPath: versionedPath,
        wasCanonicallyResolved: Data(requestedPath.utf8) != Data(versionedPath.utf8),
        propertyNames: ["svn:ignore"]
    )

    #expect(session.details.type == "property")
    #expect(Data(session.requestedPath.utf8) == Data(requestedPath.utf8))
    #expect(Data(session.versionedPath.utf8) == Data(versionedPath.utf8))
    #expect(session.wasCanonicallyResolved)
    #expect(session.propertyNames == ["svn:ignore"])
}

@Test func propertyConflictVerificationRejectsRemainingPropertyConflict() {
    let path = "공유"
    let snapshot = SVNWorkingCopySnapshot(
        statuses: [
            SVNStatusEntry(
                path: path,
                item: .unknown("normal"),
                nodeKind: .directory,
                propertyState: .conflicted
            ),
        ],
        revision: SVNWorkingCopyRevision(minimum: "2", maximum: "2"),
        collisions: [],
        versionedPathsByCanonicalKey: [path: [path]]
    )

    #expect(throws: ConflictFileError.self) {
        try PropertyConflictResolution.verifyResolved(path: path, in: snapshot)
    }
}

@Test func propertyConflictServiceReadsPropertyNameFromDirectoryPrejudiceFile() throws {
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svnmac-property-service-\(UUID().uuidString)", isDirectory: true)
    let conflictedDirectory = root.appendingPathComponent("공유", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: conflictedDirectory, withIntermediateDirectories: true)
    let prejudice = conflictedDirectory.appendingPathComponent("dir_conflicts.prej")
    try Data("Trying to change property 'svn:ignore'\n<<<<<<<\n*.tmp\n".utf8).write(to: prejudice)

    let names = PropertyConflictService().propertyNames(
        workingCopyPath: root.path,
        versionedPath: "공유",
        nodeKind: .directory
    )

    #expect(names == ["svn:ignore"])
}

@Test func propertyOnlyChangesRemainVisibleAndSelectableForCommit() {
    let entry = SVNStatusEntry(
        path: "공유",
        item: .unknown("normal"),
        nodeKind: .directory,
        propertyState: .modified
    )

    #expect(TemporaryFilePolicy.visibleEntries([entry], hideTemporaryFiles: true) == [entry])
    #expect(TemporaryFilePolicy.commitEligibleEntries([entry], hideTemporaryFiles: true) == [entry])
    #expect(entry.isSelectableForCommit)
}

@Test func propertyConflictsCannotBeSelectedForCommit() {
    let entry = SVNStatusEntry(
        path: "공유",
        item: .unknown("normal"),
        nodeKind: .directory,
        propertyState: .conflicted
    )

    #expect(!entry.isSelectableForCommit)
    #expect(TemporaryFilePolicy.commitEligibleEntries([entry], hideTemporaryFiles: false).isEmpty)
}
