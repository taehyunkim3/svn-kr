import Foundation
import Testing
@testable import SVNMac

@Test func commitHistoryRoutesActionsWithoutReplacingFileHistoryRequest() throws {
    let historyDiff = try source("HistoryRevisionDiffView.swift")
    let actions = try source("FileHistoryView.swift")

    #expect(historyDiff.contains("store.routeNextFileHistoryRequestToCommitHistory()"))
    #expect(historyDiff.contains("source: .commitHistory"))
    #expect(actions.contains("store.requestCommitHistoryRevisionRestore("))
    #expect(actions.contains("store.saveCommitHistoryRevision("))
}

private func source(_ fileName: String) throws -> String {
    try String(
        contentsOf: svnMacSources().appendingPathComponent(fileName),
        encoding: .utf8
    )
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
