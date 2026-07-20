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
