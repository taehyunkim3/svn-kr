import Testing
import SVNCore
@testable import SVNMac

@Test func untrackedPathDoubleClickTogglesOnlyDirectories() {
    #expect(UntrackedPathDoubleClick.shouldToggleExpansion(isDirectory: true))
    #expect(!UntrackedPathDoubleClick.shouldToggleExpansion(isDirectory: false))
}

@Test func untrackAndIgnoreEligibilityMatchesTrackedNonDeletedEntries() {
    #expect(UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "modified", item: .modified)))
    #expect(UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "added", item: .added)))
    #expect(UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "replaced", item: .replaced)))
    #expect(UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(
        path: "props.txt",
        item: .unknown("normal"),
        propertyState: .modified
    )))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "new", item: .unversioned)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "ignored", item: .ignored)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "deleted", item: .deleted)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "gone", item: .missing)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "conflicted", item: .conflicted)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "blocked", item: .obstructed)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "partial", item: .incomplete)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: ".", item: .modified)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(
        path: ".",
        item: .unknown("normal"),
        propertyState: .modified
    )))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(
        path: "props.txt",
        item: .unknown("normal"),
        propertyState: .conflicted
    )))
}
