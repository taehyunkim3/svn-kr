import Foundation
import Testing

@Test func projectTabsDelegateSearchToolbarOwnershipToContentView() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)
    let fileBrowser = try source(named: "WorkingCopyBrowserView.swift", in: sources)
    let history = try source(named: "HistoryView.swift", in: sources)

    #expect(contentView.contains("ProjectTabSearchModifier"))
    #expect(!fileBrowser.contains(".searchable"))
    #expect(!history.contains(".searchable"))
}

private func source(named name: String, in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}
