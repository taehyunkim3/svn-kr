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
    #expect(AppLanguage.korean.localized(.ui.incomplete.updateRequired) == "업데이트 미완료")
    #expect(AppLanguage.english.localized(.ui.incomplete.updateRequired) == "Update Incomplete")
    #expect(AppLanguage.korean.localized(.ui.switched.path) == "전환 경로")
    #expect(AppLanguage.english.localized(.ui.switched.path) == "Switched Path")
}
