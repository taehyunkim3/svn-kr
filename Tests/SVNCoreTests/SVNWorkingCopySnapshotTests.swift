import Foundation
import Testing
@testable import SVNCore

@Suite("SVNWorkingCopySnapshotTests")
struct SVNWorkingCopySnapshotTests {
    @Test func resolvesDecomposedNewChildAgainstComposedVersionedAncestor() throws {
        let decomposed = "00 사업관리/새파일.xlsx".decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            ("00 사업관리", "normal", "13302"),
            (decomposed, "unversioned", nil),
        ]))

        #expect(snapshot.statuses.map(\.path) == ["00 사업관리/새파일.xlsx"])
        #expect(snapshot.resolvedPath(for: decomposed) == "00 사업관리/새파일.xlsx")
        #expect(snapshot.revision == SVNWorkingCopyRevision(minimum: "13302", maximum: "13302"))
    }

    @Test func collapsesMissingAddedAliasTreeIntoOneCollision() throws {
        let decomposedRoot = "04 구현".decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            ("04 구현", "normal", "13302"),
            ("04 구현/기존.txt", "normal", "13302"),
            (decomposedRoot, "missing", "-1"),
            ("\(decomposedRoot)/하위", "missing", "-1"),
        ]))

        #expect(snapshot.collisions.map(\.displayPath) == ["04 구현"])
        #expect(snapshot.collisions.first?.affectedEntryCount == 2)
        #expect(snapshot.statuses.isEmpty)
    }

    @Test func keepsRealModifiedEntryAndDropsEquivalentUnversionedAlias() throws {
        let decomposed = "00 사업관리/보고서.hwp".decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            ("00 사업관리", "normal", "13302"),
            ("00 사업관리/보고서.hwp", "modified", "13302"),
            (decomposed, "unversioned", nil),
        ]))

        #expect(snapshot.statuses == [
            SVNStatusEntry(path: "00 사업관리/보고서.hwp", item: .modified, revision: "13302"),
        ])
    }

    @Test func reportsAmbiguousCanonicalVersionedPaths() throws {
        let composed = "04 구현"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            (composed, "normal", "13302"),
            (decomposed, "normal", "13301"),
        ]))

        #expect(snapshot.collisions.map(\.displayPath) == [composed])
        #expect(snapshot.resolvedPath(for: composed) == nil)
    }

    private func snapshotData(entries: [(path: String, item: String, revision: String?)]) -> Data {
        let body = entries.map { entry in
            let revision = entry.revision.map { " revision=\"\($0)\"" } ?? ""
            return "<entry path=\"\(entry.path)\"><wc-status item=\"\(entry.item)\"\(revision)/></entry>"
        }
        .joined()
        return Data("<?xml version=\"1.0\"?><status><target path=\".\">\(body)</target></status>".utf8)
    }
}
