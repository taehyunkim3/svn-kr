import Foundation
import Testing
@testable import SVNCore

@Suite("SVNWorkingCopySnapshotTests")
struct SVNWorkingCopySnapshotTests {
    @Test func exposesShortestStandaloneMissingAdditionRootForCleanup() throws {
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            ("새 폴더", "missing", "-1"),
            ("새 폴더/하위", "missing", "-1"),
            ("새 폴더/하위/문서.pdf", "missing", "-1"),
        ]))

        #expect(snapshot.missingScheduledAdditionCleanupTargets == ["새 폴더"])
        #expect(snapshot.statuses == [
            SVNStatusEntry(path: "새 폴더", item: .missing, revision: "-1"),
        ])
    }

    @Test func excludesUnsafeMissingAdditionsFromAutomaticCleanup() throws {
        let composedAlias = "별칭 폴더"
        let decomposedAlias = composedAlias.decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            (composedAlias, "normal", "13302"),
            (decomposedAlias, "missing", "-1"),
            (decomposedAlias, "unversioned", nil),
            ("혼합 폴더", "missing", "-1"),
            ("혼합 폴더/관리.txt", "modified", "13302"),
        ]))

        #expect(snapshot.missingScheduledAdditionCleanupTargets.isEmpty)
        #expect(snapshot.statuses == [
            SVNStatusEntry(path: "혼합 폴더", item: .missing, revision: "-1"),
            SVNStatusEntry(path: "혼합 폴더/관리.txt", item: .modified, revision: "13302"),
        ])
    }

    @Test func excludesTreeConflictsAndCanonicalAliasesFromAutomaticCleanup() throws {
        let composedAlias = "별칭 폴더"
        let decomposedAlias = composedAlias.decomposedStringWithCanonicalMapping
        let xml = """
        <?xml version="1.0"?>
        <status><target path=".">
          <entry path="."><wc-status item="normal" revision="13302"/></entry>
          <entry path="충돌 폴더"><wc-status item="missing" revision="-1" tree-conflicted="true"/></entry>
          <entry path="\(composedAlias)"><wc-status item="missing" revision="-1"/></entry>
          <entry path="\(decomposedAlias)"><wc-status item="unversioned"/></entry>
        </target></status>
        """
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))

        #expect(snapshot.missingScheduledAdditionCleanupTargets.isEmpty)
        #expect(snapshot.statuses.contains(
            SVNStatusEntry(path: "충돌 폴더", item: .conflicted, revision: "-1")
        ))
    }

    @Test func preservesTopLevelNFDNewPathBytes() throws {
        let rawPath = "최상위 새 폴더".decomposedStringWithCanonicalMapping
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            (rawPath, "unversioned", nil),
        ]))

        #expect(snapshot.statuses.map(\.path).map { Data($0.utf8) } == [Data(rawPath.utf8)])
        #expect(snapshot.resolvedPath(for: rawPath).map { Data($0.utf8) } == Data(rawPath.utf8))
    }

    @Test func treeConflictedCanonicalAliasIsNeverAutomaticallyRepairable() throws {
        let composed = "관리 폴더"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let xml = """
        <?xml version="1.0"?><status><target path=".">
          <entry path="."><wc-status item="normal" revision="13302"/></entry>
          <entry path="\(composed)"><wc-status item="normal" revision="13302"/></entry>
          <entry path="\(decomposed)"><wc-status item="missing" revision="-1" tree-conflicted="true"/></entry>
        </target></status>
        """
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))

        #expect(snapshot.repairableAliasPaths.isEmpty)
        #expect(snapshot.canonicalAliasRepairTargets.isEmpty)
        #expect(snapshot.statuses == [
            SVNStatusEntry(path: composed, item: .conflicted, revision: "-1"),
        ])
    }

    @Test func treeConflictBelowCanonicalAliasRootMakesWholeRootUnrepairable() throws {
        let composed = "관리 폴더"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let xml = """
        <?xml version="1.0"?><status><target path=".">
          <entry path="."><wc-status item="normal" revision="13302"/></entry>
          <entry path="\(composed)"><wc-status item="normal" revision="13302"/></entry>
          <entry path="\(decomposed)"><wc-status item="missing" revision="-1"/></entry>
          <entry path="\(decomposed)/하위.txt"><wc-status item="added" revision="-1" tree-conflicted="true"/></entry>
        </target></status>
        """
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: Data(xml.utf8))

        #expect(snapshot.repairableAliasPaths.isEmpty)
        #expect(snapshot.canonicalAliasRepairTargets.isEmpty)
        #expect(snapshot.collisions.count == 1)
        #expect(snapshot.collisions[0].canonicalPath == composed)
    }

    @Test func resolvesDecomposedNewChildAgainstComposedVersionedAncestor() throws {
        let decomposedAncestor = "00 사업관리".decomposedStringWithCanonicalMapping
        let decomposedSuffix = "0720 기획서".decomposedStringWithCanonicalMapping
        let decomposed = "\(decomposedAncestor)/\(decomposedSuffix)"
        let expected = "00 사업관리/\(decomposedSuffix)"
        let snapshot = try SVNXMLParser.workingCopySnapshot(from: snapshotData(entries: [
            (".", "normal", "13302"),
            ("00 사업관리", "normal", "13302"),
            (decomposed, "unversioned", nil),
        ]))

        #expect(snapshot.statuses.map(\.path).map { Data($0.utf8) } == [Data(expected.utf8)])
        #expect(snapshot.resolvedPath(for: decomposed).map { Data($0.utf8) } == Data(expected.utf8))
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
