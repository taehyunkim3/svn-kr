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
    #expect(AppLayout.changesDisclosureIconSize.width > 0)
    #expect(AppLayout.changesDisclosureIconSize.height > 0)
    #expect(AppLayout.changesDisclosureHitTargetSize.width > 0)
    #expect(AppLayout.changesDisclosureHitTargetSize.height > 0)
    #expect(AppLayout.changesRowSpacing > 0)
    #expect(AppLayout.untrackedChildIndentation > 0)
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

@Test func changesDisclosureHitTargetExceedsIconAndStopsBeforeToggle() {
    #expect(AppLayout.changesDisclosureIconSize.width == 18)
    #expect(AppLayout.changesDisclosureIconSize.height == 18)
    #expect(AppLayout.changesDisclosureHitTargetSize.width >= 28)
    #expect(AppLayout.changesDisclosureHitTargetSize.height >= 28)
    #expect(AppLayout.changesDisclosureHitTargetSize.width > AppLayout.changesDisclosureIconSize.width)
    #expect(AppLayout.changesDisclosureHitTargetSize.height > AppLayout.changesDisclosureIconSize.height)

    let horizontalHitExpansion = (
        AppLayout.changesDisclosureHitTargetSize.width - AppLayout.changesDisclosureIconSize.width
    ) / 2
    #expect(horizontalHitExpansion < AppLayout.changesRowSpacing)
}

@Test func sheetMinimumSizesRemainPositiveAndFitInsideDefaultWindow() {
    let sheetSizes = [
        AppLayout.addRepositorySheetMinimumSize,
        AppLayout.repositoryLocksSheetMinimumSize,
        AppLayout.ignoreRulesSheetMinimumSize,
        AppLayout.untrackAndIgnoreSheetMinimumSize,
        AppLayout.deletionConfirmationSheetMinimumSize,
        AppLayout.documentOpenConfirmationSheetMinimumSize,
        AppLayout.updatePreviewSheetMinimumSize,
        AppLayout.fileHistorySheetMinimumSize,
        AppLayout.filePropertiesSheetMinimumSize,
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
    #expect(AppLayout.commitLogHeight > 0)
    #expect(AppLayout.commitLogHeight < AppLayout.windowMinimumHeight)
    #expect(AppLayout.inlineErrorMaximumHeight > 0)
    #expect(AppLayout.inlineErrorMaximumHeight < AppLayout.pathRecoverySheetMinimumSize.height)
}

@Test func fileBrowserFolderPaneStartsAtAQuarterOfTheSplitWidth() {
    // 넉넉한 창에서는 좌측 대 우측이 1:3으로 시작해야 합니다.
    let wide: CGFloat = 1_600
    let initial = AppLayout.fileBrowserFolderPaneWidth(requested: nil, availableWidth: wide)
    #expect(initial == wide * AppLayout.fileBrowserFolderPaneWidthFraction)
    #expect(wide - initial >= AppLayout.fileBrowserContentsPaneMinimumWidth)

    // 사용자가 옮긴 위치는 두 패널의 최소 너비 안으로 갇혀야 합니다.
    #expect(
        AppLayout.fileBrowserFolderPaneWidth(requested: 10, availableWidth: wide)
            == AppLayout.fileBrowserFolderPaneMinimumWidth
    )
    #expect(
        AppLayout.fileBrowserFolderPaneWidth(requested: wide, availableWidth: wide)
            == wide - AppLayout.fileBrowserContentsPaneMinimumWidth
    )
    // 범위 안의 요청은 그대로 반영합니다.
    #expect(AppLayout.fileBrowserFolderPaneWidth(requested: 500, availableWidth: wide) == 500)

    // 좁은 창에서는 비율보다 두 패널의 최소 너비가 우선합니다.
    let narrow = AppLayout.fileBrowserFolderPaneMinimumWidth
        + AppLayout.fileBrowserContentsPaneMinimumWidth
    let narrowWidth = AppLayout.fileBrowserFolderPaneWidth(requested: nil, availableWidth: narrow)
    #expect(narrowWidth >= AppLayout.fileBrowserFolderPaneMinimumWidth)
    #expect(narrow - narrowWidth >= AppLayout.fileBrowserContentsPaneMinimumWidth)

    // 아직 크기를 모르는 첫 배치에서도 최소 너비로 안전하게 시작합니다.
    #expect(
        AppLayout.fileBrowserFolderPaneWidth(requested: nil, availableWidth: 0)
            == AppLayout.fileBrowserFolderPaneMinimumWidth
    )

    #expect(AppLayout.fileBrowserNameColumnIdealWidth > AppLayout.fileBrowserNameColumnMinimumWidth)
}
