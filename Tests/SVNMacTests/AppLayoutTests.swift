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
    #expect(AppLayout.toolbarItemHorizontalPadding > 0)
    #expect(AppLayout.aboutWindowSize.width > 0)
    #expect(AppLayout.aboutWindowSize.height > 0)
    #expect(AppLayout.aboutWindowSize.width <= AppLayout.windowDefaultWidth)
    #expect(AppLayout.aboutWindowSize.height <= AppLayout.windowDefaultHeight)
}

@Test func sheetMinimumSizesRemainPositiveAndFitInsideDefaultWindow() {
    let sheetSizes = [
        AppLayout.addRepositorySheetMinimumSize,
        AppLayout.repositoryLocksSheetMinimumSize,
        AppLayout.ignoreRulesSheetMinimumSize,
        AppLayout.deletionConfirmationSheetMinimumSize,
        AppLayout.updatePreviewSheetMinimumSize,
        AppLayout.fileHistorySheetMinimumSize,
        AppLayout.conflictResolutionSheetMinimumSize,
        AppLayout.pathRecoverySheetMinimumSize,
        AppLayout.errorDetailsSheetMinimumSize,
    ]

    for size in sheetSizes {
        #expect(size.width > 0)
        #expect(size.height > 0)
        #expect(size.width <= AppLayout.windowDefaultWidth)
        #expect(size.height <= AppLayout.windowDefaultHeight)
    }

    #expect(AppLayout.checkoutLogHeight > 0)
    #expect(AppLayout.checkoutLogHeight < AppLayout.addRepositorySheetMinimumSize.height)
    #expect(AppLayout.inlineErrorMaximumHeight > 0)
    #expect(AppLayout.inlineErrorMaximumHeight < AppLayout.pathRecoverySheetMinimumSize.height)
}
