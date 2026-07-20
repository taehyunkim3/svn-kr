import Foundation
import Testing

@Suite("ChangesViewPerformanceTests")
struct ChangesViewPerformanceTests {
    @Test func commitMessageStateIsOwnedByIsolatedControlsView() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("CommitControlsView()"))
        #expect(!changesView.contains("@State private var commitMessage"))
        #expect(commitControls.contains("@State private var commitMessage"))
    }

    @Test func changedFileListDoesNotConcatenateStatusCollections() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(!changesView.contains("store.statuses +"))
        #expect(changesView.contains("ForEach(store.statuses)"))
        #expect(changesView.contains("ForEach(store.ignoredStatuses)"))
    }

    @Test func changesViewDistinguishesMissingStatesAndSummarizesUnicodeCollisions() throws {
        let sources = try svnMacSources()
        let changesView = try source(named: "ChangesView.swift", in: sources)
        let commitControls = try source(named: "CommitControlsView.swift", in: sources)

        #expect(changesView.contains("삭제"))
        #expect(changesView.contains("로컬 누락"))
        #expect(changesView.contains("추가 취소됨"))
        #expect(changesView.contains("한글 경로 충돌"))
        #expect(changesView.contains("entry.isSelectableForCommit"))
        #expect(commitControls.contains("store.selectableStatusPaths"))
        #expect(commitControls.contains("store.canCommitSelectedPaths"))
    }

    @Test func repairableUnicodeCollisionsUseOneClickInPlaceRepair() throws {
        let changesView = try source(named: "ChangesView.swift", in: try svnMacSources())

        #expect(changesView.contains("동일 한글 경로 정리"))
        #expect(changesView.contains("if collision.repairableRawPath != nil"))
        #expect(changesView.contains("await store.repairCanonicalAliases()"))
        #expect(changesView.contains("await store.beginPathRecovery()"))
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
}
