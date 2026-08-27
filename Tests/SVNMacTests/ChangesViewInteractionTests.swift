import Testing
@testable import SVNMac

@Test func untrackedPathDoubleClickTogglesOnlyDirectories() {
    #expect(UntrackedPathDoubleClick.shouldToggleExpansion(isDirectory: true))
    #expect(!UntrackedPathDoubleClick.shouldToggleExpansion(isDirectory: false))
}
