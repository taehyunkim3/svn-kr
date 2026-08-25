import Testing
@testable import SVNMac

@Test func commitConfirmationFitsManyScrollableDeletionRows() {
    #expect(
        AppLayout.commitConfirmationSheetMinimumSize.width
            > AppLayout.deletionConfirmationSheetMinimumSize.width
    )
    #expect(
        AppLayout.commitConfirmationSheetMinimumSize.height
            > AppLayout.deletionConfirmationSheetMinimumSize.height
    )
    #expect(AppLayout.commitConfirmationSheetMinimumSize.width <= AppLayout.windowDefaultWidth)
    #expect(AppLayout.commitConfirmationSheetMinimumSize.height <= AppLayout.windowDefaultHeight)
}
