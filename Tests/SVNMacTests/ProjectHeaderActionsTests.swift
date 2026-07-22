import Foundation
import Testing

@Test func repositoryLocksActionIsOwnedByTheSharedProjectHeader() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)
    let changesView = try source(named: "ChangesView.swift", in: sources)
    let projectBadges = try source(named: "ProjectStatusBadges.swift", in: sources)
    let locksView = try source(named: "RepositoryLocksView.swift", in: sources)

    #expect(contentView.contains("private var repositoryLocksButton"))
    #expect(contentView.contains(".sheet(isPresented: $store.isShowingLocks)"))
    #expect(contentView.contains("Text(\"\\(store.repositoryLocks.count)\")"))
    #expect(!changesView.contains("$store.isShowingLocks"))
    #expect(!changesView.contains("\"잠금 목록\", \"Locks\""))
    #expect(projectBadges.contains("잠긴 파일 \\(summary.lockCount)개"))
    #expect(locksView.contains("잠금 파일은 편집 중인 파일에 다른 사용자가 동시에 커밋하지 못하도록"))
}

@Test func repositoryLocksActionAppearsBeforeOpenInFinder() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)

    let locksButton = try #require(contentView.range(of: "repositoryLocksButton"))
    let finderButton = try #require(contentView.range(of: "Button(appLanguage.text(\"Finder에서 열기\""))
    #expect(locksButton.lowerBound < finderButton.lowerBound)
}

@Test func frequentToolbarActionsKeepVisibleTextLabels() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)

    #expect(contentView.contains("Image(systemName: \"arrow.clockwise\")"))
    #expect(contentView.contains("Text(appLanguage.text(\"새로고침\", \"Refresh\"))"))
    #expect(contentView.contains("Image(systemName: \"arrow.down.circle\")"))
    #expect(contentView.contains("Text(appLanguage.text(\"업데이트\", \"Update\"))"))
    #expect(!contentView.contains("Button(appLanguage.text(\"새로고침\", \"Refresh\"), systemImage:"))
    #expect(!contentView.contains("Button(appLanguage.text(\"업데이트\", \"Update\"), systemImage:"))
}

private func source(named name: String, in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}
