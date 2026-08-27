import Foundation
import Testing

@Test func iconOnlyControlsAndStatusImagesExposeLocalizedHelp() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let changes = try source(named: "ChangesView.swift", in: sources)
    let splitBrowser = try source(named: "WorkingCopySplitBrowserView.swift", in: sources)
    let updatePreview = try source(named: "UpdatePreviewView.swift", in: sources)

    #expect(changes.contains(".help(appLanguage.localized(.ui.changes.cannotIncludeCommit))"))
    #expect(changes.contains(".help(appLanguage.localized(\n                store.expandedUntrackedDirectoryPaths.contains(path)"))
    #expect(splitBrowser.contains(".help(appLanguage.localized(\n                    browserState.expandedDirectoryPaths.contains(row.relativePath)"))
    #expect(updatePreview.contains(".help(appLanguage.localized(\n                        isExpanded"))
}

private func source(named name: String, in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}
