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
    #expect(contentView.contains("StatusBadge("))
    #expect(contentView.contains("label: \"\\(store.repositoryLocks.count)\""))
    #expect(!changesView.contains("$store.isShowingLocks"))
    #expect(!changesView.contains("\"잠금 목록\", \"Locks\""))
    #expect(projectBadges.contains("\"ui.locked.files.457daf19\""))
    #expect(locksView.contains("\"ui.a.locked.file.is.marked.on.the.svn.server.to.pre.d248a309\""))
}

@Test func repositoryLocksActionAppearsBeforeOpenInFinder() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)

    let locksButton = try #require(contentView.range(of: "repositoryLocksButton"))
    let finderButton = try #require(contentView.range(of: "Button(appLanguage.localized(\"ui.open.in.finder.35aa9225\""))
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
    #expect(contentView.contains("Text(appLanguage.localized(\"ui.refresh.0aca6bd2\"))"))
    #expect(contentView.contains("Image(systemName: \"arrow.down.circle\")"))
    #expect(contentView.contains("Text(appLanguage.localized(\"ui.update.0f38eb76\"))"))
    #expect(contentView.components(separatedBy: ".padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)").count == 4)
    #expect(!contentView.contains("Button(appLanguage.localized(\"ui.refresh.0aca6bd2\"), systemImage:"))
    #expect(!contentView.contains("Button(appLanguage.localized(\"ui.update.0f38eb76\"), systemImage:"))
}

@Test func updateAvailabilityUsesAButtonBadgeAndProgressStaysOutsideTheActionButtonGroup() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)
    let historyView = try source(named: "HistoryView.swift", in: sources)
    let projectBadges = try source(named: "ProjectStatusBadges.swift", in: sources)

    let toolbarGroupEnd = try #require(contentView.range(of: """
                .help(appLanguage.localized("ui.download.the.latest.server.changes.into.the.curr.17974067"))
                .accessibilityValue(
"""))
    let progressItem = try #require(contentView.range(of: """
            }
            ToolbarItem(placement: .navigation) {
"""))
    let availability = try #require(contentView.range(of: ".overlay(alignment: .topTrailing)"))
    let progress = try #require(contentView.range(of: "if store.showsGlobalProgress"))

    #expect(availability.lowerBound < toolbarGroupEnd.lowerBound)
    #expect(toolbarGroupEnd.lowerBound < progressItem.lowerBound)
    #expect(progressItem.lowerBound < progress.lowerBound)
    #expect(contentView.contains(".fill(.orange)"))
    #expect(contentView.contains(".frame(width: 7, height: 7)"))
    #expect(!historyView.contains("if store.isWorkingCopyOutOfDate == true"))
    #expect(projectBadges.contains("\"ui.update.0f38eb76\""))
}

@Test func mainToolbarHidesItsTitleAndKeepsProjectActionsLeading() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let app = try source(named: "SVNMacApp.swift", in: sources)
    let contentView = try source(named: "ContentView.swift", in: sources)

    #expect(app.contains(".windowToolbarStyle(.unified(showsTitle: false))"))
    #expect(contentView.contains("ToolbarItemGroup(placement: .navigation)"))
}

@Test func sidebarRemovalRequiresConfirmationForTheCapturedProject() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)
    let projectStore = try source(named: "ProjectStore.swift", in: sources)

    #expect(contentView.contains("@State private var projectPendingRemoval: SVNProject?"))
    #expect(contentView.contains("projectPendingRemoval = store.selectedProject"))
    #expect(contentView.contains("isPresented: .isPresenting($projectPendingRemoval)"))
    #expect(contentView.contains("store.removeProject(project.id)"))
    #expect(contentView.contains("role: .destructive"))
    #expect(!contentView.contains("Button(action: store.removeSelectedProject)"))
    #expect(projectStore.contains("func removeProject(_ projectID: SVNProject.ID)"))
}

private func source(named name: String, in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}
