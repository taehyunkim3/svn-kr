import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func preparesBothConflictVersionsBeforeReturningSession() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)

    let session = try service.prepareSession(
        fixture.details,
        projectID: fixture.projectID,
        workingCopyPath: fixture.workingCopy.path
    )

    #expect(try Data(contentsOf: session.mine.url) == fixture.mineBytes)
    #expect(try Data(contentsOf: session.server.url) == fixture.serverBytes)
    let mineSourceValues = try fixture.mineURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let serverSourceValues = try fixture.serverURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    #expect(session.mine.byteCount == Int64(mineSourceValues.fileSize ?? 0))
    #expect(session.server.byteCount == Int64(serverSourceValues.fileSize ?? 0))
    #expect(session.mine.modificationDate == mineSourceValues.contentModificationDate)
    #expect(session.server.modificationDate == serverSourceValues.contentModificationDate)
    #expect(session.server.revision == "42")
    #expect(session.directoryURL == session.mine.url.deletingLastPathComponent())
    #expect(session.directoryURL == session.server.url.deletingLastPathComponent())
}

@Test func usesWorkingFileAsBinaryMineWhenSVNOmitsMineArtifact() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let binaryMineBytes = Data([0x42, 0x49, 0x4E, 0x00, 0xFF])
    try binaryMineBytes.write(to: fixture.workingFileURL)
    let details = SVNConflictDetails(
        path: fixture.details.path,
        type: fixture.details.type,
        operation: fixture.details.operation,
        previousBaseFile: fixture.details.previousBaseFile,
        myFile: nil,
        serverFile: fixture.details.serverFile,
        previousRevision: fixture.details.previousRevision,
        serverRevision: fixture.details.serverRevision
    )

    let session = try ConflictFileService(backupRootURL: fixture.backupRoot).prepareSession(
        details,
        projectID: fixture.projectID,
        workingCopyPath: fixture.workingCopy.path
    )

    #expect(try Data(contentsOf: session.mine.url) == binaryMineBytes)
}

@Test func binaryMineResolveUsesPreparedVersionAndRecoversLatestWorkingEdit() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let binaryMineBytes = Data([0x42, 0x49, 0x4E, 0x00, 0xFF])
    try binaryMineBytes.write(to: fixture.workingFileURL)
    let details = SVNConflictDetails(
        path: fixture.details.path,
        type: fixture.details.type,
        operation: fixture.details.operation,
        myFile: nil,
        serverFile: fixture.details.serverFile,
        serverRevision: fixture.details.serverRevision
    )
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let session = try service.prepareSession(
        details,
        projectID: fixture.projectID,
        workingCopyPath: fixture.workingCopy.path
    )
    try Data("edited comparison copy".utf8).write(to: session.mine.url)
    let latestWorkingBytes = Data([0x4C, 0x41, 0x54, 0x45, 0x00, 0xFE])
    try latestWorkingBytes.write(to: fixture.workingFileURL)

    let recoveryURL = try service.prepareWorkingFileForResolve(
        for: session,
        choice: .mineFull,
        workingCopyPath: fixture.workingCopy.path
    )

    #expect(try Data(contentsOf: recoveryURL) == latestWorkingBytes)
    #expect(try Data(contentsOf: fixture.workingFileURL) == binaryMineBytes)
}

@Test func preservesLatestWorkingFileBytesImmediatelyBeforeResolve() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let session = try service.prepareSession(
        fixture.details,
        projectID: fixture.projectID,
        workingCopyPath: fixture.workingCopy.path
    )
    let latestBytes = Data([0x6C, 0x61, 0x74, 0x65, 0x73, 0x74, 0x00, 0xFF])
    try latestBytes.write(to: fixture.workingFileURL)

    let recoveryURL = try service.preserveWorkingFile(
        for: session,
        workingCopyPath: fixture.workingCopy.path
    )

    #expect(recoveryURL.deletingLastPathComponent() == session.directoryURL)
    #expect(recoveryURL.lastPathComponent.hasPrefix("."))
    #expect(try Data(contentsOf: recoveryURL) == latestBytes)
}

@Test func failedWorkingRecoveryCopyLeavesNoFinalRecoveryFile() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    var copyCount = 0
    let service = ConflictFileService(
        backupRootURL: fixture.backupRoot,
        copyItem: { source, destination in
            copyCount += 1
            if copyCount == 3 {
                try Data("partial recovery".utf8).write(to: destination)
                throw FixtureCopyError.failed
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    )
    let session = try service.prepareSession(
        fixture.details,
        projectID: fixture.projectID,
        workingCopyPath: fixture.workingCopy.path
    )

    #expect(throws: FixtureCopyError.self) {
        try service.preserveWorkingFile(for: session, workingCopyPath: fixture.workingCopy.path)
    }

    let hiddenFiles = try FileManager.default.contentsOfDirectory(
        at: session.directoryURL,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix(".") }
    #expect(hiddenFiles.isEmpty)
}

@Test func removesPartialSessionWhenServerVersionIsMissing() throws {
    let fixture = try ConflictFixture(includesServerFile: false)
    defer { fixture.remove() }
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)

    let error = #expect(throws: ConflictFileError.self) {
        try service.prepareSession(
            fixture.details,
            projectID: fixture.projectID,
            workingCopyPath: fixture.workingCopy.path
        )
    }
    guard case .missingServer = error else {
        Issue.record("서버 파일 누락 오류를 반환해야 합니다.")
        return
    }

    #expect(try fixture.sessionDirectories().isEmpty)
}

@Test func rejectsRelativeConflictSourceOutsideWorkingCopy() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let outsideFile = fixture.root.appendingPathComponent("outside.mine")
    try fixture.mineBytes.write(to: outsideFile)
    let details = fixture.details(replacingMineFileWith: "../outside.mine")

    let error = #expect(throws: ConflictFileError.self) {
        try service.prepareSession(details, projectID: fixture.projectID, workingCopyPath: fixture.workingCopy.path)
    }
    guard case .sourceOutsideWorkingCopy = error else {
        Issue.record("상대 경로가 working copy 밖을 가리키면 거부해야 합니다.")
        return
    }
    #expect(try fixture.sessionDirectories().isEmpty)
}

@Test func acceptsAbsoluteConflictSourcesInsideSymlinkResolvedWorkingCopy() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let workingCopyLink = fixture.root.appendingPathComponent("working-copy-link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: workingCopyLink, withDestinationURL: fixture.workingCopy)
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let details = fixture.details(
        replacingMineFileWith: fixture.mineURL.path,
        replacingServerFileWith: fixture.serverURL.path
    )

    let session = try service.prepareSession(
        details,
        projectID: fixture.projectID,
        workingCopyPath: workingCopyLink.path
    )

    #expect(try Data(contentsOf: session.mine.url) == fixture.mineBytes)
    #expect(try Data(contentsOf: session.server.url) == fixture.serverBytes)
}

@Test func rejectsAbsoluteConflictSourceOutsideSymlinkResolvedWorkingCopy() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let outsideFile = fixture.root.appendingPathComponent("outside.mine")
    try fixture.mineBytes.write(to: outsideFile)
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let details = fixture.details(replacingMineFileWith: outsideFile.path)

    let error = #expect(throws: ConflictFileError.self) {
        try service.prepareSession(
            details,
            projectID: fixture.projectID,
            workingCopyPath: fixture.workingCopy.path
        )
    }
    guard case .sourceOutsideWorkingCopy = error else {
        Issue.record("절대 경로도 symlink 해석된 working copy 밖이면 거부해야 합니다.")
        return
    }
    #expect(try fixture.sessionDirectories().isEmpty)
}

@Test func rejectsBackupRootInsideWorkingCopy() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let backupRoot = fixture.workingCopy.appendingPathComponent(".conflict-backups", isDirectory: true)
    let service = ConflictFileService(backupRootURL: backupRoot)

    let error = #expect(throws: ConflictFileError.self) {
        try service.prepareSession(fixture.details, projectID: fixture.projectID, workingCopyPath: fixture.workingCopy.path)
    }
    guard case .backupRootInsideWorkingCopy = error else {
        Issue.record("working copy 안의 백업 루트는 거부해야 합니다.")
        return
    }
    #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
}

@Test func rejectsDirectoryConflictSource() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let directory = fixture.workingCopy.appendingPathComponent("conflicts/directory.mine", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let details = fixture.details(replacingMineFileWith: "conflicts/directory.mine")

    let error = #expect(throws: ConflictFileError.self) {
        try service.prepareSession(details, projectID: fixture.projectID, workingCopyPath: fixture.workingCopy.path)
    }
    guard case .unsafeMineSource = error else {
        Issue.record("디렉터리는 충돌 소스로 사용할 수 없습니다.")
        return
    }
    #expect(try fixture.sessionDirectories().isEmpty)
}

@Test func rejectsSymbolicLinkConflictSource() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let link = fixture.workingCopy.appendingPathComponent("conflicts/document.server-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.serverURL)
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)
    let details = fixture.details(replacingServerFileWith: "conflicts/document.server-link")

    let error = #expect(throws: ConflictFileError.self) {
        try service.prepareSession(details, projectID: fixture.projectID, workingCopyPath: fixture.workingCopy.path)
    }
    guard case .unsafeServerSource = error else {
        Issue.record("심볼릭 링크는 충돌 소스로 사용할 수 없습니다.")
        return
    }
    #expect(try fixture.sessionDirectories().isEmpty)
}

@Test func removesStagingFilesWhenSecondCopyFails() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    var copyCount = 0
    var firstDestination: URL?
    let service = ConflictFileService(
        backupRootURL: fixture.backupRoot,
        copyItem: { source, destination in
            copyCount += 1
            if copyCount == 2 { throw FixtureCopyError.failed }
            try FileManager.default.copyItem(at: source, to: destination)
            firstDestination = destination
        }
    )

    #expect(throws: FixtureCopyError.self) {
        try service.prepareSession(fixture.details, projectID: fixture.projectID, workingCopyPath: fixture.workingCopy.path)
    }

    #expect(copyCount == 2)
    #expect(firstDestination != nil)
    #expect(!FileManager.default.fileExists(atPath: firstDestination?.path ?? ""))
    #expect(try fixture.sessionDirectories().isEmpty)
}

@Test func omitsUnsafeServerRevisionFromBackupFilename() throws {
    let fixture = try ConflictFixture()
    defer { fixture.remove() }
    let service = ConflictFileService(backupRootURL: fixture.backupRoot)

    for revision in ["42/../outside", "../outside"] {
        let session = try service.prepareSession(
            fixture.details(replacingServerRevisionWith: revision),
            projectID: fixture.projectID,
            workingCopyPath: fixture.workingCopy.path
        )

        #expect(session.server.url.deletingLastPathComponent() == session.directoryURL)
        #expect(session.server.url.lastPathComponent == "document_서버파일.txt")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("outside").path))
    }
}

private final class ConflictFixture {
    let root: URL
    let workingCopy: URL
    let backupRoot: URL
    let projectID = UUID()
    let mineBytes = Data("mine bytes".utf8)
    let serverBytes = Data("server bytes".utf8)
    let details: SVNConflictDetails
    let mineURL: URL
    let serverURL: URL
    let workingFileURL: URL

    init(includesServerFile: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)

        mineURL = workingCopy.appendingPathComponent("conflicts/document.mine")
        serverURL = workingCopy.appendingPathComponent("conflicts/document.server")
        try FileManager.default.createDirectory(at: mineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try mineBytes.write(to: mineURL)
        if includesServerFile {
            try serverBytes.write(to: serverURL)
        }
        workingFileURL = workingCopy.appendingPathComponent("Documents/document.txt")
        try FileManager.default.createDirectory(
            at: workingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("working conflict markers".utf8).write(to: workingFileURL)
        details = SVNConflictDetails(
            path: "Documents/document.txt",
            type: "text",
            operation: "update",
            myFile: "conflicts/document.mine",
            serverFile: "conflicts/document.server",
            serverRevision: "42"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func details(
        replacingMineFileWith mineFile: String? = nil,
        replacingServerFileWith serverFile: String? = nil,
        replacingServerRevisionWith serverRevision: String? = nil
    ) -> SVNConflictDetails {
        SVNConflictDetails(
            path: details.path,
            type: details.type,
            operation: details.operation,
            myFile: mineFile ?? details.myFile,
            serverFile: serverFile ?? details.serverFile,
            serverRevision: serverRevision ?? details.serverRevision
        )
    }

    func sessionDirectories() throws -> [URL] {
        let projectRoot = backupRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: projectRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: projectRoot, includingPropertiesForKeys: nil)
    }
}

private enum FixtureCopyError: Error {
    case failed
}
