import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func treeConflictMetadataExplainsLocalAndServerChanges() {
    let details = SVNConflictDetails(
        path: "보고서.xlsx",
        type: "tree",
        operation: "update",
        treeConflictAction: "edit",
        treeConflictReason: "delete",
        treeConflictKind: "file"
    )

    #expect(
        TreeConflictPresentation.description(for: details, language: .korean)
            == "로컬: 삭제 · 서버: 수정 · 대상: 파일"
    )
    #expect(
        TreeConflictPresentation.description(for: details, language: .english)
            == "Local: Deleted · Server: Modified · Target: File"
    )
}

@Test func treeConflictMetadataPreservesUnknownValues() {
    let details = SVNConflictDetails(
        path: "새형식",
        type: "tree",
        operation: "future-operation",
        treeConflictAction: "future-action",
        treeConflictReason: "future-reason",
        treeConflictKind: "future-kind"
    )

    #expect(
        TreeConflictPresentation.description(for: details, language: .english)
            == "Local: future-reason · Server: future-action · Target: future-kind"
    )
}

@Test func treeConflictViewShowsParsedMetadata() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("TreeConflictResolutionView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("TreeConflictPresentation.description("))
    #expect(source.contains("for: session.details"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
