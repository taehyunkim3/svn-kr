import Foundation
import Testing
@testable import SVNMac

@Test func bulkUnlockAlertDoesNotRenderDebugErrorDescriptions() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("RepositoryLocksView.swift"),
        encoding: .utf8
    )
    let detailsStart = try #require(source.range(of: "private func bulkUnlockResultDetails"))
    let details = source[detailsStart.lowerBound...]

    #expect(details.contains("BulkUnlockResultPresentation.failureList"))
    #expect(!details.contains("$0.message"))
}

@Test func bulkUnlockFailureListContainsPathsButNoInternalErrorDescriptions() {
    let result = BulkUnlockResult(
        requestedCount: 3,
        releasedPaths: ["docs/성공.xlsx"],
        failures: [
            BulkUnlockFailure(
                path: "docs/실패.xlsx",
                message: "SVNError.commandFailed(command: unlock, message: denied)"
            ),
            BulkUnlockFailure(
                path: "docs/실패2.hwp",
                message: "LockWorkflowTestError.denied"
            ),
        ]
    )

    let details = BulkUnlockResultPresentation.failureList(result)
    #expect(details == "docs/실패.xlsx\ndocs/실패2.hwp")
    #expect(!details.contains("SVNError"))
    #expect(!details.contains("LockWorkflowTestError"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
