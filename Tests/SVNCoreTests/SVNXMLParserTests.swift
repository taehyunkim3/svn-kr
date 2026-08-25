import Foundation
import Testing
@testable import SVNCore

@Test func parsesOnlyChangedStatuses() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="Sources/App.swift"><wc-status item="modified" revision="12"/></entry>
      <entry path="README.md"><wc-status item="normal" revision="12"/></entry>
      <entry path="new.txt"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    let entries = try SVNXMLParser.statuses(from: Data(xml.utf8))
    #expect(entries.map(\.path) == ["Sources/App.swift", "new.txt"])
    #expect(entries.map(\.item) == [.modified, .unversioned])
}

@Test func parsesModifiedPropertyStatusOnNormalItem() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="1" props="modified"/></entry>
    </target></status>
    """

    let entry = try #require(SVNXMLParser.statuses(from: Data(xml.utf8)).first)

    #expect(entry.item.rawValue == "normal")
    #expect(entry.propertyState == .modified)
    #expect(entry.isSelectableForCommit)
}

@Test func parsesConflictedPropertyStatusOnNormalItem() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status props="conflicted" item="normal" revision="2"/></entry>
    </target></status>
    """

    let entry = try #require(SVNXMLParser.statuses(from: Data(xml.utf8)).first)

    #expect(entry.propertyState == .conflicted)
    #expect(!entry.isSelectableForCommit)
}

@Test func discardsNormalItemWithoutPropertyChanges() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="2" props="none"/></entry>
      <entry path="README.md"><wc-status item="normal" revision="2" props="normal"/></entry>
    </target></status>
    """

    #expect(try SVNXMLParser.statuses(from: Data(xml.utf8)).isEmpty)
}

@Test func preservesSwitchedNormalItem() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="Sources"><wc-status item="normal" revision="2" props="none" switched="true"/></entry>
      <entry path="README.md"><wc-status item="normal" revision="2" props="none"/></entry>
    </target></status>
    """

    let entry = try #require(SVNXMLParser.statuses(from: Data(xml.utf8)).first)

    #expect(entry.path == "Sources")
    #expect(entry.item.rawValue == "normal")
    #expect(entry.isSwitched)
    #expect(entry.isSelectableForCommit)
}

@Test func parsesIncompleteStatusAsKnownAlias() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="partial"><wc-status item="incomplete" revision="2" props="none"/></entry>
    </target></status>
    """

    let entry = try #require(SVNXMLParser.statuses(from: Data(xml.utf8)).first)

    #expect(entry.item == .incomplete)
    #expect(entry.item.rawValue == "incomplete")
}

@Test func parsesObstructedStatusWithoutChangingUnknownFallback() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="blocked"><wc-status item="obstructed" revision="3" props="none"/></entry>
      <entry path="future"><wc-status item="future-status" revision="3" props="none"/></entry>
    </target></status>
    """

    let entries = try SVNXMLParser.statuses(from: Data(xml.utf8))

    #expect(entries.map(\.item) == [.obstructed, .unknown("future-status")])
    #expect(entries.map(\.item.rawValue) == ["obstructed", "future-status"])
}

@Test func parsesWorkingCopyEntriesAndOnlyRepositoryBackedEntriesAreVersioned() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="Documents"><wc-status item="normal" revision="12"/></entry>
      <entry path="Documents/plan.pptx"><wc-status item="normal" revision="12"/></entry>
      <entry path="new.txt"><wc-status item="added" revision="-1"/></entry>
      <entry path="draft.txt"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    let entries = try SVNXMLParser.workingCopyEntries(from: Data(xml.utf8))
    #expect(entries.map(\.path) == ["Documents", "Documents/plan.pptx", "new.txt", "draft.txt"])
    #expect(entries.map(\.isVersioned) == [true, true, false, false])
}

@Test func parsesWorkingCopyPropertyAndSwitchedMetadataFromVerboseStatus() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="12" props="none"/></entry>
      <entry path="Documents"><wc-status props="modified" item="normal" revision="12"/></entry>
      <entry path="Sources"><wc-status switched="true" item="normal" revision="12" props="none"/></entry>
    </target></status>
    """

    let entries = try SVNXMLParser.workingCopyEntries(from: Data(xml.utf8))

    #expect(entries.map(\.propertyState) == [.none, .modified, .none])
    #expect(entries.map(\.isSwitched) == [false, false, true])
}

@Test func parsesSingleWorkingCopyRevision() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="13295"/></entry>
      <entry path="README.md"><wc-status item="normal" revision="13295"/></entry>
    </target></status>
    """
    let revision = try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    #expect(revision.minimum == "13295")
    #expect(revision.maximum == "13295")
    #expect(revision.displayValue == "13295")
    #expect(revision.timelineRevision == "13295")
    #expect(!revision.isMixed)
}

@Test func parsesMixedWorkingCopyRevisionRange() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="13292"/></entry>
      <entry path="Sources/App.swift"><wc-status item="normal" revision="13295"/></entry>
      <entry path="draft.txt"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    let revision = try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    #expect(revision.minimum == "13292")
    #expect(revision.maximum == "13295")
    #expect(revision.displayValue == "13292–13295")
    #expect(revision.timelineRevision == "13295")
    #expect(revision.isMixed)
}

@Test func ignoresScheduledAdditionsWhenCalculatingWorkingCopyRevision() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="13295"/></entry>
      <entry path="new.txt"><wc-status item="added" revision="-1"/></entry>
    </target></status>
    """
    let revision = try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    #expect(revision.minimum == "13295")
    #expect(revision.maximum == "13295")
}

@Test func rejectsWorkingCopyRevisionWithoutVersionedEntries() {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="draft.txt"><wc-status item="unversioned"/></entry>
    </target></status>
    """
    #expect(throws: SVNError.self) {
        try SVNXMLParser.workingCopyRevision(from: Data(xml.utf8))
    }
}

@Test func parsesRecursiveIgnoreRules() throws {
    let xml = """
    <?xml version="1.0"?><properties>
      <target path="."><property name="svn:ignore">.DS_Store
    *.log
    </property></target>
      <target path="Documents"><property name="svn:ignore">~$*
    </property></target>
    </properties>
    """
    let rules = try SVNXMLParser.ignoreRules(from: Data(xml.utf8))
    #expect(rules == [
        SVNIgnoreRule(directory: ".", pattern: ".DS_Store"),
        SVNIgnoreRule(directory: ".", pattern: "*.log"),
        SVNIgnoreRule(directory: "Documents", pattern: "~$*"),
    ])
}

@Test func parsesLocalGlobalAndInheritedIgnoreRules() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <properties>
      <target path=".">
        <property name="svn:ignore">.DS_Store
    </property>
        <property name="svn:global-ignores">*.tmp
    </property>
      </target>
      <target path="https://example.com/svn/trunk">
        <inherited_property name="svn:global-ignores">node_modules
    </inherited_property>
      </target>
    </properties>
    """

    let rules = try SVNXMLParser.ignoreRules(from: Data(xml.utf8))

    #expect(rules == [
        SVNIgnoreRule(directory: ".", pattern: ".DS_Store", propertyKind: .local),
        SVNIgnoreRule(directory: ".", pattern: "*.tmp", propertyKind: .global),
        SVNIgnoreRule(
            directory: ".",
            pattern: "node_modules",
            propertyKind: .global,
            inheritedFrom: "https://example.com/svn/trunk"
        ),
    ])
}

@Test func parsesRepositoryLocksFromRemoteStatus() throws {
    let xml = """
    <?xml version="1.0"?><status><target path="."><entry path="Documents/plan.pptx">
      <wc-status item="normal" revision="10"/>
      <repos-status item="none" props="none"><lock><token>token-1</token><owner>tester</owner><comment>editing</comment><created>2026-07-16T01:02:03.000000Z</created></lock></repos-status>
    </entry></target></status>
    """
    let locks = try SVNXMLParser.repositoryLocks(fromStatus: Data(xml.utf8))
    #expect(locks.count == 1)
    #expect(locks[0].path == "Documents/plan.pptx")
    #expect(locks[0].owner == "tester")
    #expect(locks[0].comment == "editing")
    #expect(locks[0].created != nil)
}

@Test func parsesConflictArtifactsAndHidesTemporaryStatusEntries() throws {
    let statusXML = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="sample.txt"><wc-status item="conflicted" revision="3" props="none"/></entry>
      <entry path="sample.txt.mine"><wc-status item="unversioned" props="none"/></entry>
      <entry path="sample.txt.r2"><wc-status item="unversioned" props="none"/></entry>
      <entry path="sample.txt.r3"><wc-status item="unversioned" props="none"/></entry>
    </target></status>
    """
    #expect(try SVNXMLParser.statuses(from: Data(statusXML.utf8)).map(\.path) == ["sample.txt"])

    let infoXML = """
    <?xml version="1.0"?><info><entry kind="file" path="sample.txt" revision="3"><conflict operation="update" type="text">
      <version kind="file" revision="2" side="source-left"/><version kind="file" revision="3" side="source-right"/>
      <prev-base-file>/tmp/sample.txt.r2</prev-base-file><prev-wc-file>/tmp/sample.txt.mine</prev-wc-file><cur-base-file>/tmp/sample.txt.r3</cur-base-file>
    </conflict></entry></info>
    """
    let details = try SVNXMLParser.conflictDetails(fromInfo: Data(infoXML.utf8))
    #expect(details?.path == "sample.txt")
    #expect(details?.myFile == "/tmp/sample.txt.mine")
    #expect(details?.serverRevision == "3")
}

@Test func hidesCanonicallyEquivalentConflictArtifacts() throws {
    let conflicted = "00 사업관리/주간보고서.hwp"
    let decomposed = conflicted.decomposedStringWithCanonicalMapping
    let statusXML = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="\(conflicted)"><wc-status item="conflicted" revision="42" props="none"/></entry>
      <entry path="\(decomposed).mine"><wc-status item="unversioned" props="none"/></entry>
      <entry path="\(decomposed).r41"><wc-status item="unversioned" props="none"/></entry>
      <entry path="\(decomposed).r42"><wc-status item="unversioned" props="none"/></entry>
      <entry path="\(decomposed).review"><wc-status item="unversioned" props="none"/></entry>
    </target></status>
    """

    let paths = try SVNXMLParser.statuses(from: Data(statusXML.utf8)).map(\.path)

    #expect(paths.map { Data($0.utf8) } == [
        Data(conflicted.utf8),
        Data("\(decomposed).review".utf8),
    ])
}

@Test func parsesTreeConflictFromRealSVNInfoShape() throws {
    let infoXML = """
    <?xml version="1.0"?><info><entry kind="file" path="tree.txt" revision="2">
      <tree-conflict kind="file" reason="edit" victim="tree.txt" action="delete" operation="update">
        <version kind="file" revision="2" side="source-left"/>
        <version kind="none" revision="3" side="source-right"/>
      </tree-conflict>
    </entry></info>
    """

    let details = try SVNXMLParser.conflictDetails(fromInfo: Data(infoXML.utf8))

    #expect(details?.path == "tree.txt")
    #expect(details?.type == "tree")
    #expect(details?.operation == "update")
    #expect(details?.previousRevision == "2")
    #expect(details?.serverRevision == "3")
    #expect(details?.treeConflictAction == "delete")
    #expect(details?.treeConflictReason == "edit")
    #expect(details?.treeConflictKind == "file")
}

@Test func parsesTreeConflictMetadataFromNestedConflictShape() throws {
    let infoXML = """
    <?xml version="1.0"?><info><entry kind="dir" path="tree" revision="4">
      <conflict operation="switch" type="tree">
        <tree-conflict kind="dir" reason="missing" victim="tree" action="replace">
          <version kind="dir" revision="3" side="source-left"/>
          <version kind="dir" revision="4" side="source-right"/>
        </tree-conflict>
      </conflict>
    </entry></info>
    """

    let details = try SVNXMLParser.conflictDetails(fromInfo: Data(infoXML.utf8))

    #expect(details?.path == "tree")
    #expect(details?.type == "tree")
    #expect(details?.operation == "switch")
    #expect(details?.previousRevision == "3")
    #expect(details?.serverRevision == "4")
    #expect(details?.treeConflictAction == "replace")
    #expect(details?.treeConflictReason == "missing")
    #expect(details?.treeConflictKind == "dir")
}

@Test func leavesTreeConflictMetadataNilForContentConflict() throws {
    let infoXML = """
    <?xml version="1.0"?><info><entry kind="file" path="sample.txt" revision="3">
      <conflict operation="update" type="text">
        <version kind="file" revision="2" side="source-left"/>
        <version kind="file" revision="3" side="source-right"/>
      </conflict>
    </entry></info>
    """

    let details = try SVNXMLParser.conflictDetails(fromInfo: Data(infoXML.utf8))

    #expect(details?.type == "text")
    #expect(details?.treeConflictAction == nil)
    #expect(details?.treeConflictReason == nil)
    #expect(details?.treeConflictKind == nil)
}

@Test func detectsActualRemoteWorkingCopyChanges() throws {
    let upToDateXML = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="."><wc-status item="normal" revision="13282"/><repos-status item="none" props="none"/></entry>
      <against revision="13283"/>
    </target></status>
    """
    let outOfDateXML = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="Sources/App.swift"><wc-status item="normal" revision="13282"/><repos-status item="modified" props="none"/></entry>
      <against revision="13283"/>
    </target></status>
    """

    #expect(try !SVNXMLParser.workingCopyIsOutOfDate(from: Data(upToDateXML.utf8)))
    #expect(try SVNXMLParser.workingCopyIsOutOfDate(from: Data(outOfDateXML.utf8)))
}

@Test func parsesIncomingServerChangesForUpdatePreview() throws {
    let xml = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="Sources/App.swift"><wc-status item="normal" revision="10"/><repos-status item="modified" props="none"/></entry>
      <entry path="Documents/old.pptx"><wc-status item="normal" revision="10"/><repos-status item="deleted" props="none"/></entry>
      <entry path="README.md"><wc-status item="normal" revision="10"/><repos-status item="none" props="none"/></entry>
    </target></status>
    """
    let changes = try SVNXMLParser.remoteChanges(from: Data(xml.utf8))
    #expect(changes.map(\.path) == ["Sources/App.swift", "Documents/old.pptx"])
    #expect(changes.map(\.item) == [.modified, .deleted])
}

@Test func parsesLogHistory() throws {
    let xml = """
    <?xml version="1.0"?><log><logentry revision="13267">
      <author>thkim</author><date>2026-07-15T01:02:03.123456Z</date><msg>master 소스 반영</msg>
      <paths>
        <path action="M" prop-mods="false" text-mods="true" kind="file">/trunk/Sources/App.swift</path>
        <path action="A" prop-mods="true" text-mods="false" kind="dir" copyfrom-path="/branches/work" copyfrom-rev="13260">/trunk/Feature</path>
      </paths>
      <revprops><property name="author-email">thkim@example.com</property><property name="reviewer">lee</property></revprops>
    </logentry></log>
    """
    let entries = try SVNXMLParser.logs(from: Data(xml.utf8))
    #expect(entries.count == 1)
    #expect(entries[0].revision == "13267")
    #expect(entries[0].author == "thkim")
    #expect(entries[0].email == "thkim@example.com")
    #expect(entries[0].date != nil)
    #expect(entries[0].message == "master 소스 반영")
    #expect(entries[0].changedPaths.count == 2)
    #expect(entries[0].changedPaths[0].path == "/trunk/Sources/App.swift")
    #expect(entries[0].changedPaths[0].action == .modified)
    #expect(entries[0].changedPaths[0].textModified == true)
    #expect(entries[0].changedPaths[1].copyFromPath == "/branches/work")
    #expect(entries[0].changedPaths[1].copyFromRevision == "13260")
    #expect(entries[0].revisionProperties.map(\.name) == ["author-email", "reviewer"])
}

@Test func repairsLegacyUTF8MojibakeInLogMessages() throws {
    let intended = "전자정부프레임워크 4.3 추가"
    let decomposed = intended.decomposedStringWithCanonicalMapping
    let mojibake = String(data: Data(decomposed.utf8), encoding: .isoLatin1)!
    let xml = """
    <?xml version="1.0"?><log>
      <logentry revision="13285">
        <author>jude</author><date>2026-07-16T05:33:47.501907Z</date>
        <msg>\(mojibake)</msg>
      </logentry>
      <logentry revision="13286"><revprops>
        <property name="svn:log">\(mojibake)</property>
      </revprops></logentry>
    </log>
    """

    let entries = try SVNXMLParser.logs(from: Data(xml.utf8))

    #expect(entries.map(\.message) == [intended, intended])
    #expect(entries.map(\.originalMessage) == [mojibake, mojibake])
}

@Test func leavesOriginalMessageEmptyWhenLogMessageNeedsNoRepair() throws {
    let xml = """
    <?xml version="1.0"?><log><logentry revision="13287">
      <author>tester</author><msg>정상 한글 메시지</msg>
    </logentry></log>
    """

    let entries = try SVNXMLParser.logs(from: Data(xml.utf8))

    #expect(entries[0].message == "정상 한글 메시지")
    #expect(entries[0].originalMessage == nil)
}

@Test func parsesStandardRevisionPropertiesAndDateWithoutFractionalSeconds() throws {
    let xml = """
    <?xml version="1.0"?><log><logentry revision="13268"><revprops>
      <property name="svn:author">thkim</property>
      <property name="svn:date">2026-07-15T01:02:03Z</property>
      <property name="svn:log">revprop 형식 커밋</property>
    </revprops></logentry></log>
    """

    let entries = try SVNXMLParser.logs(from: Data(xml.utf8))

    #expect(entries.count == 1)
    #expect(entries[0].author == "thkim")
    #expect(entries[0].date != nil)
    #expect(entries[0].message == "revprop 형식 커밋")
    #expect(entries[0].revisionProperties.isEmpty)
}

@Test func placesWorkingCopyRevisionInHistoryTimeline() {
    let logs = [50, 49, 47, 46].map { revision in
        SVNLogEntry(
            revision: String(revision),
            author: "tester",
            date: nil,
            message: "r\(revision)"
        )
    }

    let exact = SVNHistoryTimeline(logs: logs, workingCopyRevision: "49")
    #expect(exact.graphEntryRevision == "49")
    #expect(exact.insertionIndex == nil)

    let betweenEntries = SVNHistoryTimeline(logs: logs, workingCopyRevision: "48")
    #expect(betweenEntries.graphEntryRevision == nil)
    #expect(betweenEntries.insertionIndex == 2)

    let olderThanLoadedHistory = SVNHistoryTimeline(logs: logs, workingCopyRevision: "40")
    #expect(olderThanLoadedHistory.isBeforeLoadedHistory)

    let newerThanHead = SVNHistoryTimeline(logs: logs, workingCopyRevision: "51")
    #expect(newerThanHead.graphEntryRevision == "50")

    let mixed = SVNWorkingCopyRevision(minimum: "47", maximum: "50")
    let mixedTimeline = SVNHistoryTimeline(logs: logs, workingCopyRevision: mixed.timelineRevision)
    #expect(mixedTimeline.graphEntryRevision == "50")
}

@Test func preservesUnknownSVNValuesForForwardCompatibility() throws {
    let statusXML = """
    <?xml version="1.0"?><status><target path=".">
      <entry path="future.txt"><wc-status item="future-status"/></entry>
    </target></status>
    """
    let logXML = """
    <?xml version="1.0"?><log><logentry revision="1"><paths>
      <path action="X" kind="future-kind">/future.txt</path>
    </paths></logentry></log>
    """

    let status = try #require(SVNXMLParser.statuses(from: Data(statusXML.utf8)).first)
    #expect(status.item == .unknown("future-status"))
    #expect(status.item.rawValue == "future-status")

    let changedPath = try #require(SVNXMLParser.logs(from: Data(logXML.utf8)).first?.changedPaths.first)
    #expect(changedPath.action == .unknown("X"))
    #expect(changedPath.kind == .unknown("future-kind"))
}
