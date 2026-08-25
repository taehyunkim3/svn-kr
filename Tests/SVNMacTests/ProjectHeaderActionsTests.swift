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
    #expect(projectBadges.contains(".ui.locked.files"))
    #expect(locksView.contains(".ui.a.lockedFileIsMarkedOnTheSvnServerToPre"))
}

@Test func repositoryLocksActionAppearsBeforeOpenInFinder() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)

    let locksButton = try #require(contentView.range(of: "repositoryLocksButton"))
    let finderButton = try #require(contentView.range(of: "Button(appLanguage.localized(.ui.localizationOpen.inFinder"))
    #expect(locksButton.lowerBound < finderButton.lowerBound)
}

@Test func repositoryPathNormalizationRequiresAnExplicitProjectHeaderAction() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)
    let normalizationView = try source(
        named: "RepositoryPathNormalizationView.swift",
        in: sources
    )

    #expect(contentView.contains("private var repositoryPathNormalizationButton"))
    #expect(contentView.contains("Task { await store.beginRepositoryPathNormalization() }"))
    #expect(contentView.contains(".sheet(isPresented: $store.isShowingRepositoryPathNormalization)"))
    #expect(!normalizationView.contains(".task"))
}

@Test func appSettingsAreReachableFromTheSidebarFooter() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)

    // 상단 메뉴에만 있던 전체 설정을 사이드바 하단에서도 열 수 있어야 합니다.
    #expect(contentView.contains("SettingsLink"))
    #expect(contentView.contains(".ui.settings.label"))
    #expect(contentView.contains("systemImage: \"gearshape\""))

    // 작업 폴더 추가/삭제 버튼과 같은 묶음에 있어야 합니다.
    let removeButton = try #require(
        contentView.range(of: "projectPendingRemoval = store.selectedProject")
    )
    let settingsLink = try #require(contentView.range(of: "SettingsLink"))
    let sidebarSpacer = try #require(contentView.range(of: "Spacer()"))
    #expect(removeButton.lowerBound < settingsLink.lowerBound)
    #expect(settingsLink.lowerBound < sidebarSpacer.lowerBound)
}

@Test func frequentToolbarActionsKeepVisibleTextLabels() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)

    #expect(contentView.contains("Image(systemName: \"arrow.clockwise\")"))
    #expect(contentView.contains("Text(appLanguage.localized(.ui.refresh.label))"))
    #expect(contentView.contains("Image(systemName: \"arrow.down.circle\")"))
    #expect(contentView.contains("Text(appLanguage.localized(.ui.update.label))"))
    #expect(contentView.components(separatedBy: ".padding(.horizontal, AppLayout.toolbarItemHorizontalPadding)").count == 4)
    #expect(!contentView.contains("Button(appLanguage.localized(.ui.refresh.label), systemImage:"))
    #expect(!contentView.contains("Button(appLanguage.localized(.ui.update.label), systemImage:"))
}

@Test func updateAvailabilityUsesASeparatedButtonBadgeAndProgressStaysOutsideTheActionButtonGroup() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let contentView = try source(named: "ContentView.swift", in: sources)
    let historyView = try source(named: "HistoryView.swift", in: sources)
    let projectBadges = try source(named: "ProjectStatusBadges.swift", in: sources)

    let toolbarGroupEnd = try #require(contentView.range(of: """
                .help(appLanguage.localized(.ui.download.theLatestServerChangesIntoTheCurr))
                .accessibilityValue(
"""))
    let progressItem = try #require(contentView.range(of: """
            }
            ToolbarItem(placement: .navigation) {
"""))
    let availability = try #require(contentView.range(of: "if let badgeText = store.incomingUpdateCommitBadgeText"))
    let progress = try #require(contentView.range(of: "if store.showsGlobalProgress"))

    #expect(availability.lowerBound < toolbarGroupEnd.lowerBound)
    #expect(toolbarGroupEnd.lowerBound < progressItem.lowerBound)
    #expect(progressItem.lowerBound < progress.lowerBound)
    #expect(!contentView.contains(".overlay(alignment: .topTrailing)"))
    #expect(contentView.contains(".offset(y: -6)"))
    #expect(contentView.contains(".background(.red, in: Capsule())"))
    #expect(!historyView.contains("if store.isWorkingCopyOutOfDate == true"))
    #expect(projectBadges.contains(".ui.update.label"))
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
