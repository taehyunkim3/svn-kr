import Foundation
import Testing
@testable import SVNMac

@Test func commitMessageInputUsesProjectOwnedDrafts() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("CommitControlsView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("@State private var commitMessageDrafts"))
    #expect(source.contains("guard store.selectedProjectID == submissionProjectID else { return }"))
    #expect(source.contains(".onChange(of: store.selectedProjectID)"))
    #expect(!source.contains("@State private var commitMessage ="))
}

@Test func commitMessageDraftsPreserveEachProjectWithoutCrossFilling() {
    let firstProjectID = UUID()
    let secondProjectID = UUID()
    var drafts = CommitMessageDrafts()

    drafts.setMessage("첫 프로젝트 긴 메시지", for: firstProjectID)
    #expect(drafts.message(for: secondProjectID).isEmpty)

    drafts.setMessage("둘째 프로젝트 메시지", for: secondProjectID)
    #expect(drafts.message(for: firstProjectID) == "첫 프로젝트 긴 메시지")
    #expect(drafts.message(for: secondProjectID) == "둘째 프로젝트 메시지")

    drafts.clearMessage(for: secondProjectID)
    #expect(drafts.message(for: firstProjectID) == "첫 프로젝트 긴 메시지")
    #expect(drafts.message(for: secondProjectID).isEmpty)
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
