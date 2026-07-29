import Foundation
import Testing
@testable import SVNMac

@Test func historyTimeZonesAreUniqueAndContainDefaults() {
    for language in AppLanguage.allCases {
        let zones = AppSettings.historyTimeZones(for: language)
        #expect(Set(zones.map(\.identifier)).count == zones.count)
        #expect(zones.contains { $0.identifier == AppSettings.defaultHistoryTimeZone })
        #expect(zones.contains { $0.identifier == AppSettings.systemHistoryTimeZone })
    }
}

@Test func appLanguagesProvideStableNativeNames() {
    #expect(AppLanguage.korean.displayName == "한국어")
    #expect(AppLanguage.english.displayName == "English")
}

@Test func stringCatalogHonorsExplicitAppLanguageAndFormatArguments() {
    #expect(AppLanguage.korean.localized("ui.close.3ea43db3") == "닫기")
    #expect(AppLanguage.english.localized("ui.close.3ea43db3") == "Close")
    #expect(
        AppLanguage.korean.localized("error.choose.missing.items", "문서/누락.txt")
            == "먼저 로컬 누락 항목의 처리 방법을 선택하세요: 문서/누락.txt"
    )
    #expect(
        AppLanguage.english.localized("error.choose.missing.items", "Docs/missing.txt")
            == "Choose how to handle locally missing items first: Docs/missing.txt"
    )
    #expect(
        AppLanguage.korean.localized(
            "ui.remove.working.folder.from.app.confirmation.54d24642",
            "Atlas Mobile"
        ) == "'Atlas Mobile' 등록을 해제할까요?"
    )
    #expect(
        AppLanguage.english.localized(
            "ui.remove.working.folder.from.app.confirmation.54d24642",
            "Atlas Mobile"
        ) == "Remove 'Atlas Mobile' from the app?"
    )
}
