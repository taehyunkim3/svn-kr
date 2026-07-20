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
    #expect(session.mine.byteCount == Int64(fixture.mineBytes.count))
    #expect(session.server.byteCount == Int64(fixture.serverBytes.count))
    #expect(session.mine.modificationDate != nil)
    #expect(session.server.modificationDate != nil)
    #expect(session.server.revision == "42")
    #expect(session.directoryURL == session.mine.url.deletingLastPathComponent())
    #expect(session.directoryURL == session.server.url.deletingLastPathComponent())
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

    let projectRoot = fixture.backupRoot.appendingPathComponent(fixture.projectID.uuidString, isDirectory: true)
    let sessionDirectories = try FileManager.default.contentsOfDirectory(at: projectRoot, includingPropertiesForKeys: nil)
    #expect(sessionDirectories.isEmpty)
}

private final class ConflictFixture {
    let root: URL
    let workingCopy: URL
    let backupRoot: URL
    let projectID = UUID()
    let mineBytes = Data("mine bytes".utf8)
    let serverBytes = Data("server bytes".utf8)
    let details: SVNConflictDetails

    init(includesServerFile: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)

        let mineURL = workingCopy.appendingPathComponent("conflicts/document.mine")
        let serverURL = workingCopy.appendingPathComponent("conflicts/document.server")
        try FileManager.default.createDirectory(at: mineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try mineBytes.write(to: mineURL)
        if includesServerFile {
            try serverBytes.write(to: serverURL)
        }
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
}
