import Foundation
import Testing

@Test func needsLockMenuUsesSelectedProjectActionGuard() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("ChangesView.swift"),
        encoding: .utf8
    )
    let menuStart = try #require(source.range(of: "Menu {", options: .backwards))
    let menuSource = source[menuStart.lowerBound...]

    #expect(menuSource.contains(".ui.lock.requireLockBeforeEditing"))
    #expect(menuSource.contains(".disabled(store.isSelectedProjectActionBlocked)"))
    #expect(!menuSource.contains(".disabled(store.isWorking)"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
