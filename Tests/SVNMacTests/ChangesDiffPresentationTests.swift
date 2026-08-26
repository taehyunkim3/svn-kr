import Foundation
import Testing

@Test func changesDiffUsesSharedLineHighlightingView() throws {
    let sources = svnMacSources()
    let changes = try String(
        contentsOf: sources.appendingPathComponent("ChangesView.swift"),
        encoding: .utf8
    )
    let diff = try String(
        contentsOf: sources.appendingPathComponent("DiffTextView.swift"),
        encoding: .utf8
    )

    #expect(changes.contains("DiffTextView(store.diffContent.localizedText(appLanguage))"))
    #expect(!changes.contains("Text(store.diffContent.localizedText(appLanguage))"))
    #expect(diff.contains("attributedLine.foregroundColor = .green"))
    #expect(diff.contains("attributedLine.foregroundColor = .red"))
    #expect(diff.contains("!line.hasPrefix(\"+++\")"))
    #expect(diff.contains("!line.hasPrefix(\"---\")"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
