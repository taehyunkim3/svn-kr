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
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "new", item: .unversioned)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "ignored", item: .ignored)))
    #expect(!UntrackAndIgnoreRequest.isEligible(SVNStatusEntry(path: "deleted", item: .deleted)))
}
