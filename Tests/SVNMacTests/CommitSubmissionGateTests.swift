import Foundation
import Testing
@testable import SVNMac

@Suite("CommitSubmissionGateTests")
struct CommitSubmissionGateTests {
    @Test func beginCommitSubmissionRejectsSecondCallUntilEnded() {
        var state = ProjectRecoveryState()

        let first = state.beginCommitSubmission(isActionBlocked: false, canCommit: true)
        let second = state.beginCommitSubmission(isActionBlocked: false, canCommit: true)

        #expect(first != nil)
        #expect(second == nil)
        #expect(state.commitSubmissionID == first)

        state.endCommitSubmission(first!)
        let third = state.beginCommitSubmission(isActionBlocked: false, canCommit: true)
        #expect(third != nil)
        #expect(state.commitSubmissionID == third)
    }

    @Test func beginCommitSubmissionRejectsBlockedOrEmptySelection() {
        var blocked = ProjectRecoveryState()
        var emptySelection = ProjectRecoveryState()

        #expect(blocked.beginCommitSubmission(isActionBlocked: true, canCommit: true) == nil)
        #expect(emptySelection.beginCommitSubmission(isActionBlocked: false, canCommit: false) == nil)
        #expect(blocked.commitSubmissionID == nil)
        #expect(emptySelection.commitSubmissionID == nil)
    }

    @Test func endCommitSubmissionIgnoresStaleToken() {
        var state = ProjectRecoveryState()
        let first = state.beginCommitSubmission(isActionBlocked: false, canCommit: true)
        let stale = UUID()

        state.endCommitSubmission(stale)
        #expect(state.commitSubmissionID == first)

        state.endCommitSubmission(first!)
        #expect(state.commitSubmissionID == nil)
    }

    @Test func commitMessageReturnAcquiresSubmissionTokenBeforeYield() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/SVNMac/CommitControlsView.swift"),
            encoding: .utf8
        )
        let functionStart = try #require(
            source.range(of: "private func submitCommitAfterEndingTextInput()")
        )
        let fromFunction = source[functionStart.lowerBound...]
        let taskStart = try #require(fromFunction.range(of: "Task {"))
        let beforeTask = String(fromFunction[..<taskStart.lowerBound])

        #expect(beforeTask.contains("beginCommitSubmission"))
        #expect(source.contains("endCommitSubmission"))
        #expect(source.contains("isSelectedProjectActionBlocked"))
        #expect(source.contains("canCommitSelectedPaths"))
    }
}
