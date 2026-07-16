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
