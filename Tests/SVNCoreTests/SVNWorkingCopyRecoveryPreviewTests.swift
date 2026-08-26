import Foundation
import Testing
@testable import SVNCore

/// 복구는 파일 내용만 복사한다. svn 속성과 switched 상태는 재현하지 못하므로,
/// 그런 항목은 매핑에 넣어 "옮겼다"고 보고하는 대신 차단 목록으로 보내야 한다.
@Suite("SVNWorkingCopyRecoveryPreviewTests")
struct SVNWorkingCopyRecoveryPreviewTests {
    @Test func propertyOnlyChangeIsBlockedInsteadOfSilentlyDropped() throws {
        let fixture = try RecoveryPreviewFixture(files: ["문서.txt"])
        defer { fixture.remove() }

        let snapshot = try SVNWorkingCopySnapshot(entries: [
            SVNWorkingCopyEntry(path: ".", status: "normal", revision: "10"),
            SVNWorkingCopyEntry(
                path: "문서.txt",
                status: "normal",
                revision: "10",
                propertyState: .modified
            ),
        ])
        let preview = SVNWorkingCopyRecovery.preview(
            sourcePath: fixture.source.path,
            snapshot: snapshot
        )

        #expect(preview.blockingPaths == ["문서.txt"])
        #expect(preview.mappings.isEmpty)
    }

    @Test func switchedEntryIsBlockedInsteadOfSilentlyDropped() throws {
        let fixture = try RecoveryPreviewFixture(files: ["분기.txt"])
        defer { fixture.remove() }

        let snapshot = try SVNWorkingCopySnapshot(entries: [
            SVNWorkingCopyEntry(path: ".", status: "normal", revision: "10"),
            SVNWorkingCopyEntry(path: "분기.txt", status: "normal", revision: "10", isSwitched: true),
        ])
        let preview = SVNWorkingCopyRecovery.preview(
            sourcePath: fixture.source.path,
            snapshot: snapshot
        )

        #expect(preview.blockingPaths == ["분기.txt"])
        #expect(preview.mappings.isEmpty)
    }

    @Test func modifiedFileWithPropertyChangeIsBlocked() throws {
        let fixture = try RecoveryPreviewFixture(files: ["표.xlsx"])
        defer { fixture.remove() }

        let snapshot = try SVNWorkingCopySnapshot(entries: [
            SVNWorkingCopyEntry(path: ".", status: "normal", revision: "10"),
            SVNWorkingCopyEntry(
                path: "표.xlsx",
                status: "modified",
                revision: "10",
                propertyState: .modified
            ),
        ])
        let preview = SVNWorkingCopyRecovery.preview(
            sourcePath: fixture.source.path,
            snapshot: snapshot
        )

        #expect(preview.blockingPaths == ["표.xlsx"])
        #expect(preview.mappings.isEmpty)
    }

    /// 미리보기 숫자에 세지 않는 항목이 매핑에 남으면 복사 없이 migratedPaths에만 들어간다.
    @Test func everyMappingIsCountedInThePreviewTotals() throws {
        let fixture = try RecoveryPreviewFixture(files: ["가.txt", "나.txt", "다.txt"])
        defer { fixture.remove() }

        let snapshot = try SVNWorkingCopySnapshot(entries: [
            SVNWorkingCopyEntry(path: ".", status: "normal", revision: "10"),
            SVNWorkingCopyEntry(path: "가.txt", status: "modified", revision: "10"),
            SVNWorkingCopyEntry(path: "나.txt", status: "unversioned"),
            SVNWorkingCopyEntry(path: "다.txt", status: "normal", revision: "10", propertyState: .modified),
            SVNWorkingCopyEntry(path: "라.txt", status: "missing", revision: "10"),
        ])
        let preview = SVNWorkingCopyRecovery.preview(
            sourcePath: fixture.source.path,
            snapshot: snapshot
        )

        let counted = preview.modifiedCount + preview.addedCount + preview.deletedCount
        #expect(counted == preview.mappings.count)
    }
}

private struct RecoveryPreviewFixture {
    let root: URL
    let source: URL

    init(files: [String]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-recovery-preview-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for file in files {
            try Data("내용".utf8).write(to: source.appendingPathComponent(file))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
