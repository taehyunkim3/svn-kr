import Foundation
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
    #expect(AppLayout.settingsWindowSize.width <= AppLayout.windowDefaultWidth)
    #expect(AppLayout.settingsWindowSize.height <= AppLayout.windowDefaultHeight)
    #expect(AppLayout.credentialFieldMinimumWidth <= AppLayout.credentialsSheetWidth)
    #expect(AppLayout.logMessagePopoverMinimumWidth <= AppLayout.logMessagePopoverIdealWidth)
    #expect(AppLayout.logMessagePopoverIdealWidth <= AppLayout.logMessagePopoverMaximumWidth)
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
        AppLayout.repositoryPathNormalizationSheetMinimumSize,
        AppLayout.repositoryPathNormalizationConfirmationSheetMinimumSize,
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

@Test func fileBrowserFolderPaneStartsAtAQuarterOfTheSplitWidth() {
    // 넉넉한 창에서는 좌측 대 우측이 1:3으로 시작해야 합니다.
    let wide: CGFloat = 1_600
    let idealForWide = AppLayout.fileBrowserFolderPaneIdealWidth(availableWidth: wide)
    #expect(idealForWide == wide * AppLayout.fileBrowserFolderPaneWidthFraction)
    #expect(wide - idealForWide >= AppLayout.fileBrowserContentsPaneMinimumWidth)

    // 좁은 창에서는 비율보다 두 패널의 최소 너비가 우선합니다.
    let narrow = AppLayout.fileBrowserFolderPaneMinimumWidth
        + AppLayout.fileBrowserContentsPaneMinimumWidth
    let idealForNarrow = AppLayout.fileBrowserFolderPaneIdealWidth(availableWidth: narrow)
    #expect(idealForNarrow >= AppLayout.fileBrowserFolderPaneMinimumWidth)
    #expect(narrow - idealForNarrow >= AppLayout.fileBrowserContentsPaneMinimumWidth)

    // 아직 크기를 모르는 첫 배치에서도 최소 너비로 안전하게 시작합니다.
    #expect(
        AppLayout.fileBrowserFolderPaneIdealWidth(availableWidth: 0)
            == AppLayout.fileBrowserFolderPaneMinimumWidth
    )

    #expect(AppLayout.fileBrowserNameColumnIdealWidth > AppLayout.fileBrowserNameColumnMinimumWidth)
}
