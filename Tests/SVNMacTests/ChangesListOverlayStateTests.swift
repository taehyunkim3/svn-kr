import Testing
@testable import SVNMac

@Suite("ChangesListOverlayStateTests")
struct ChangesListOverlayStateTests {
    @Test func visibleChangesRemainVisibleWhileRefreshing() {
        #expect(resolve(visibleStatusCount: 1, refreshActivity: .refreshing) == .hidden)
    }

    @Test func emptyChangesShowLoadingWhileRefreshing() {
        #expect(resolve(refreshActivity: .refreshing) == .loading)
    }

    @Test func emptyChangesShowEmptyStateWhileIdle() {
        #expect(resolve(refreshActivity: .idle) == .empty)
    }

    @Test func visibleIgnoredChangesRemainVisibleWhileRefreshing() {
        #expect(resolve(
            visibleIgnoredStatusCount: 1,
            ignoredFileVisibility: .shown,
            refreshActivity: .refreshing
        ) == .hidden)
    }

    private func resolve(
        pathCollisionCount: Int = 0,
        visibleStatusCount: Int = 0,
        visibleIgnoredStatusCount: Int = 0,
        ignoredFileVisibility: ChangesListOverlayState.IgnoredFileVisibility = .hidden,
        refreshActivity: ChangesListOverlayState.RefreshActivity
    ) -> ChangesListOverlayState {
        ChangesListOverlayState.resolve(
            pathCollisionCount: pathCollisionCount,
            visibleStatusCount: visibleStatusCount,
            visibleIgnoredStatusCount: visibleIgnoredStatusCount,
            ignoredFileVisibility: ignoredFileVisibility,
            refreshActivity: refreshActivity
        )
    }
}
