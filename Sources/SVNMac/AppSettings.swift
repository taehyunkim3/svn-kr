import Foundation
import SwiftUI

enum AppSettings {
    // UserDefaults 키와 기본값을 한곳에 모아 화면과 앱 시작 코드가 같은 설정을
    // 사용하도록 합니다. 문자열 키가 여러 파일에 흩어지는 것을 막는 역할입니다.
    static let languageKey = "app-language"
    static let defaultLanguage = AppLanguage.korean.rawValue
    static let historyTimeZoneKey = "history-time-zone"
    static let defaultHistoryTimeZone = "Asia/Seoul"
    static let systemHistoryTimeZone = "__system__"
    static let hideTemporaryFilesKey = "hide-temporary-files"
    static let defaultHideTemporaryFiles = true
    static let fileBrowserViewModeKey = "file-browser-view-mode"
    static let defaultFileBrowserViewMode = FileBrowserViewMode.split.rawValue
    static let documentOpenLockPolicyKey = "document-open-lock-policy"
    static let defaultDocumentOpenLockPolicy = DocumentOpenLockPolicy.askEveryTime.rawValue

    static func hideTemporaryFiles(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: hideTemporaryFilesKey) != nil else {
            return defaultHideTemporaryFiles
        }
        return defaults.bool(forKey: hideTemporaryFilesKey)
    }

    static func fileBrowserViewMode(in defaults: UserDefaults = .standard) -> FileBrowserViewMode {
        let identifier = defaults.string(forKey: fileBrowserViewModeKey)
            ?? defaultFileBrowserViewMode
        return FileBrowserViewMode(rawValue: identifier) ?? .split
    }

    static func documentOpenLockPolicy(
        in defaults: UserDefaults = .standard
    ) -> DocumentOpenLockPolicy {
        let identifier = defaults.string(forKey: documentOpenLockPolicyKey)
            ?? defaultDocumentOpenLockPolicy
        return DocumentOpenLockPolicy(rawValue: identifier) ?? .askEveryTime
    }

    static func setDocumentOpenLockPolicy(
        _ policy: DocumentOpenLockPolicy,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(policy.rawValue, forKey: documentOpenLockPolicyKey)
    }

    static func historyTimeZones(for language: AppLanguage) -> [(identifier: String, label: String)] {
        [
            ("Asia/Seoul", language.localized(.ui.settings.koreaStandardTime)),
            (systemHistoryTimeZone, language.localized(.ui.settings.macSystemTimeZone, TimeZone.current.identifier)),
            ("UTC", language.localized(.ui.settings.coordinatedUniversalTimeUtc)),
            ("Asia/Tokyo", language.localized(.ui.settings.japanStandardTime)),
            ("America/Los_Angeles", language.localized(.ui.settings.usPacificTime)),
            ("America/New_York", language.localized(.ui.settings.usEasternTime)),
            ("Europe/London", language.localized(.ui.settings.ukTime)),
        ].reduce(into: []) { result, item in
            if !result.contains(where: { $0.identifier == item.0 }) {
                result.append((identifier: item.0, label: item.1))
            }
        }
    }
}

enum DocumentOpenLockPolicy: String, CaseIterable {
    case askEveryTime = "ask-every-time"
    case alwaysOpenWithoutLock = "always-open-without-lock"
    case alwaysLockAndOpen = "always-lock-and-open"
}

enum FileBrowserViewMode: String, CaseIterable {
    case tree
    case split
}

enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    var displayName: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppSettings.languageKey) ?? AppSettings.defaultLanguage) ?? .korean
    }

    func localized(_ key: LocalizationKey) -> String {
        localizedBundle.localizedString(
            forKey: key.rawValue,
            value: key.rawValue,
            table: nil
        )
    }

    func localized(_ key: LocalizationKey, _ arguments: Any...) -> String {
        let format = localized(key)
        let stringArguments: [CVarArg] = arguments.map { String(describing: $0) }
        return String(
            format: format,
            locale: Locale(identifier: rawValue),
            arguments: stringArguments
        )
    }

    private var localizedBundle: Bundle {
        let resources = packagedResourceBundle ?? .module
        guard let path = resources.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resources
        }
        return bundle
    }

    private var packagedResourceBundle: Bundle? {
        guard let url = Bundle.main.url(forResource: "SVNMac_SVNMac", withExtension: "bundle") else {
            return nil
        }
        return Bundle(url: url)
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.korean
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

struct AppSettingsView: View {
    // @AppStorage를 사용해 변경 즉시 UserDefaults와 앱 환경에 반영합니다.
    @AppStorage(AppSettings.languageKey)
    private var languageIdentifier = AppSettings.defaultLanguage
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone
    @AppStorage(AppSettings.hideTemporaryFilesKey)
    private var hideTemporaryFiles = AppSettings.defaultHideTemporaryFiles
    @AppStorage(AppSettings.documentOpenLockPolicyKey)
    private var documentOpenLockPolicyIdentifier = AppSettings.defaultDocumentOpenLockPolicy

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageIdentifier) ?? .korean
    }

    private var documentOpenLockPolicy: DocumentOpenLockPolicy {
        DocumentOpenLockPolicy(rawValue: documentOpenLockPolicyIdentifier) ?? .askEveryTime
    }

    var body: some View {
        Form {
            Picker(appLanguage.localized(.ui.settings.language), selection: $languageIdentifier) {
                Text("한국어").tag(AppLanguage.korean.rawValue)
                Text("English").tag(AppLanguage.english.rawValue)
            }
            .help(appLanguage.localized(.ui.settings.chooseLanguageUsedAppInterface))

            Picker(appLanguage.localized(.ui.settings.commitDisplayTimeZone), selection: $historyTimeZoneIdentifier) {
                ForEach(AppSettings.historyTimeZones(for: appLanguage), id: \.identifier) { timeZone in
                    Text(timeZone.label).tag(timeZone.identifier)
                }
            }
            .help(appLanguage.localized(.ui.settings.chooseTimeZoneUsedCommitDatesTimes))

            Text(appLanguage.localized(.ui.settings.defaultKoreaStandardTimeKstDoesNotChangeOriginalCommit))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                appLanguage.localized(.ui.settings.hideMacOfficeTemporaryFiles),
                isOn: $hideTemporaryFiles
            )
            .help(appLanguage.localized(.ui.settings.hideTemporaryFilesChangesPreventThemCommittedVersionedFilesRemain))

            Picker(
                appLanguage.localized(.ui.settings.whenOpeningDocuments),
                selection: $documentOpenLockPolicyIdentifier
            ) {
                Text(
                    appLanguage.localized(.ui.settings.askEveryTime)
                )
                    .tag(DocumentOpenLockPolicy.askEveryTime.rawValue)
                Text(
                    appLanguage.localized(.ui.settings.alwaysOpenWithoutLockingAsking)
                )
                    .tag(DocumentOpenLockPolicy.alwaysOpenWithoutLock.rawValue)
                Text(
                    appLanguage.localized(.ui.settings.alwaysLockOpenWithoutAsking)
                )
                    .tag(DocumentOpenLockPolicy.alwaysLockAndOpen.rawValue)
            }

            if documentOpenLockPolicy == .alwaysLockAndOpen {
                Label(
                    appLanguage.localized(
                        .ui.settings.otherUsersCannotModifyLockedFileUntilCommitItRelease
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(
            width: AppLayout.settingsWindowSize.width,
            height: AppLayout.settingsWindowSize.height
        )
    }
}
