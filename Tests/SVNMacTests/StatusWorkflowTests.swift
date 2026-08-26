import Testing
import SVNCore
@testable import SVNMac

@Test func incompleteStatusRequiresUpdateAndBlocksRevert() {
    let entry = SVNStatusEntry(path: "Documents/report.xlsx", item: .incomplete)

    #expect(!WorkingCopyStatusPolicy.allowsRevert(entry))
    #expect(WorkingCopyStatusPolicy.showsIncompleteRecovery(entry))
    #expect(WorkingCopyStatusPolicy.tone(for: entry.item) == .red)
}

@Test func obstructedAndSwitchedStatusesExposeTheirWarnings() {
    let obstructed = SVNStatusEntry(path: "Documents/report.xlsx", item: .obstructed)
    let switched = SVNStatusEntry(path: "Documents", item: .modified, isSwitched: true)

    #expect(WorkingCopyStatusPolicy.showsObstructionGuidance(obstructed))
    #expect(WorkingCopyStatusPolicy.tone(for: obstructed.item) == .orange)
    #expect(WorkingCopyStatusPolicy.showsSwitchedWarning(switched))
}

@Test func statusWarningsHaveKoreanAndEnglishLabels() {
    #expect(AppLanguage.korean.localized(.ui.update.incomplete) == "업데이트 미완료")
    #expect(AppLanguage.english.localized(.ui.update.incomplete) == "Update Incomplete")
    #expect(AppLanguage.korean.localized(.ui.changes.switchedPath) == "전환 경로")
    #expect(AppLanguage.english.localized(.ui.changes.switchedPath) == "Switched Path")
}
