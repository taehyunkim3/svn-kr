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

@Test func temporaryFilesAreHiddenByDefault() {
    let defaults = UserDefaults(suiteName: "temporary-files-default-\(UUID().uuidString)")!

    #expect(AppSettings.defaultHideTemporaryFiles)
    #expect(AppSettings.hideTemporaryFiles(in: defaults))

    defaults.set(false, forKey: AppSettings.hideTemporaryFilesKey)
    #expect(!AppSettings.hideTemporaryFiles(in: defaults))
}

@Test func documentOpenLockPolicyDefaultsToAskingEveryTime() {
    let defaults = UserDefaults(suiteName: "document-open-policy-default-\(UUID().uuidString)")!

    #expect(AppSettings.defaultDocumentOpenLockPolicy == DocumentOpenLockPolicy.askEveryTime.rawValue)
    #expect(AppSettings.documentOpenLockPolicy(in: defaults) == .askEveryTime)
}

@Test func documentOpenLockPoliciesAreStoredAndRestored() {
    let defaults = UserDefaults(suiteName: "document-open-policy-storage-\(UUID().uuidString)")!

    for policy in DocumentOpenLockPolicy.allCases {
        AppSettings.setDocumentOpenLockPolicy(policy, in: defaults)
        #expect(AppSettings.documentOpenLockPolicy(in: defaults) == policy)
    }

    defaults.set("unknown-policy", forKey: AppSettings.documentOpenLockPolicyKey)
    #expect(AppSettings.documentOpenLockPolicy(in: defaults) == .askEveryTime)
}

@Test func stringCatalogHonorsExplicitAppLanguageAndFormatArguments() {
    #expect(AppLanguage.korean.localized(.ui.close.label) == "닫기")
    #expect(AppLanguage.english.localized(.ui.close.label) == "Close")
    #expect(
        AppLanguage.korean.localized(.error.chooseMissingItems, "문서/누락.txt")
            == "먼저 로컬 누락 항목의 처리 방법을 선택하세요: 문서/누락.txt"
    )
    #expect(
        AppLanguage.english.localized(.error.chooseMissingItems, "Docs/missing.txt")
            == "Choose how to handle locally missing items first: Docs/missing.txt"
    )
    #expect(
        AppLanguage.korean.localized(
            .ui.remove.workingFolderFromAppConfirmation,
            "Atlas Mobile"
        ) == "'Atlas Mobile' 등록을 해제할까요?"
    )
    #expect(
        AppLanguage.english.localized(
            .ui.remove.workingFolderFromAppConfirmation,
            "Atlas Mobile"
        ) == "Remove 'Atlas Mobile' from the app?"
    )
}
