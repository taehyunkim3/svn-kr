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

@Test func appLanguagesProvideStableNativeNamesAndFallback() {
    #expect(AppLanguage.korean.displayName == "한국어")
    #expect(AppLanguage.english.displayName == "English")
    #expect(AppLanguage.korean.text("한국어 문구", "English copy") == "한국어 문구")
    #expect(AppLanguage.english.text("한국어 문구", "English copy") == "English copy")
}
