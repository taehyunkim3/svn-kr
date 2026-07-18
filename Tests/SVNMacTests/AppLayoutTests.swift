import Testing
@testable import SVNMac

@Test func minimumWindowCanContainSidebarAndWorkspacePanels() {
    #expect(
        AppLayout.sidebarMinimumWidth
            + AppLayout.historyPrimaryMinimumWidth
            + AppLayout.historyDetailMinimumWidth
            <= AppLayout.windowMinimumWidth
    )
    #expect(
        AppLayout.sidebarMinimumWidth
            + AppLayout.changesPrimaryMinimumWidth
            + AppLayout.changesDetailMinimumWidth
            <= AppLayout.windowMinimumWidth
    )
}

@Test func layoutSizeRangesRemainOrdered() {
    #expect(AppLayout.sidebarMinimumWidth <= AppLayout.sidebarIdealWidth)
    #expect(AppLayout.sidebarIdealWidth <= AppLayout.sidebarMaximumWidth)
    #expect(AppLayout.windowMinimumWidth <= AppLayout.windowDefaultWidth)
    #expect(AppLayout.windowMinimumHeight <= AppLayout.windowDefaultHeight)
}
