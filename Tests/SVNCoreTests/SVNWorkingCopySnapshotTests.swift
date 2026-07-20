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

    @Test func exposesOneToOneMissingFileAliasAsReplacementCandidate() throws {
        let composed = "00 사업관리/주간보고서.hwp"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13304"),
            ("00 사업관리", "normal", "13304"),
            (composed, "missing", "13304"),
            (decomposed, "unversioned", nil),
        ]))

        #expect(snapshot.canonicalFileReplacements == [
            SVNCanonicalFileReplacement(
                versionedPath: composed,
                localAliasPath: decomposed,
                revision: "13304"
            ),
        ])
    }

    @Test func doesNotExposeAmbiguousUnversionedAliasesAsReplacementCandidate() throws {
        let composed = "reports/\u{1EB9}\u{301}.hwp"
        let decomposed = "reports/e\u{323}\u{301}.hwp"
        let secondRawAlias = "reports/e\u{301}\u{323}.hwp"
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13304"),
            ("reports", "normal", "13304"),
            (composed, "missing", "13304"),
            (decomposed, "unversioned", nil),
            (secondRawAlias, "unversioned", nil),
        ]))

        #expect(snapshot.canonicalFileReplacements.isEmpty)
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

    @Test func exposesShortestMissingAliasRootAsRepairableDespiteEquivalentUnversionedEntries() throws {
        let composedRoot = "04 구현"
        let nfdRoot = composedRoot.decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            (composedRoot, "normal", "13302"),
            (nfdRoot, "missing", "-1"),
            ("\(nfdRoot)/하위", "missing", "-1"),
            ("\(nfdRoot)/하위/파일.txt", "missing", "-1"),
            ("\(nfdRoot)/실제수정.bin", "added", "-1"),
            (nfdRoot, "unversioned", nil),
            ("\(nfdRoot)/하위/새파일.txt", "unversioned", nil),
        ]))

        #expect(snapshot.repairableAliasPaths.map { Data($0.utf8) } == [Data(nfdRoot.utf8)])
        #expect(snapshot.canonicalAliasRepairTargets.map { Data($0.utf8) } == [
            Data("\(nfdRoot)/하위/파일.txt".utf8),
            Data("\(nfdRoot)/실제수정.bin".utf8),
            Data("\(nfdRoot)/하위".utf8),
            Data(nfdRoot.utf8),
        ])
        #expect(snapshot.collisions.first?.affectedEntryCount == 4)
        #expect(!snapshot.hasUnrepairablePathCollisions)
    }

    @Test func reportsAmbiguousVersionedAliasRootAsUnrepairable() throws {
        let composedRoot = "04 구현"
        let nfdRoot = composedRoot.decomposedStringWithCanonicalMapping
        let ambiguous = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            (composedRoot, "normal", "13302"),
            (nfdRoot, "normal", "13301"),
            (nfdRoot, "missing", "-1"),
        ]))

        #expect(ambiguous.repairableAliasPaths.isEmpty)
        #expect(ambiguous.hasUnrepairablePathCollisions)
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
