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

    static func historyTimeZones(for language: AppLanguage) -> [(identifier: String, label: String)] {
        [
            ("Asia/Seoul", language.localized("ui.korea.standard.time.kst.utc.9.74d019be")),
            (systemHistoryTimeZone, language.localized("ui.mac.system.time.zone.df3e6992", TimeZone.current.identifier)),
            ("UTC", language.localized("ui.coordinated.universal.time.utc.0b7fc6d7")),
            ("Asia/Tokyo", language.localized("ui.japan.standard.time.jst.utc.9.04744dfc")),
            ("America/Los_Angeles", language.localized("ui.us.pacific.time.5c9c3b6f")),
            ("America/New_York", language.localized("ui.us.eastern.time.9e917cad")),
            ("Europe/London", language.localized("ui.uk.time.46ba8995")),
        ].reduce(into: []) { result, item in
            if !result.contains(where: { $0.identifier == item.0 }) {
                result.append((identifier: item.0, label: item.1))
            }
        }
    }
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

    func localized(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func localized(_ key: String, _ arguments: Any...) -> String {
        let format = localized(key)
        let stringArguments: [CVarArg] = arguments.map { String(describing: $0) }
        return String(
            format: format,
            locale: Locale(identifier: rawValue),
            arguments: stringArguments
        )
    }

    private var localizedBundle: Bundle {
        guard let path = Bundle.module.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
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

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: languageIdentifier) ?? .korean
    }

    var body: some View {
        Form {
            Picker(appLanguage.localized("ui.language.8e5b78fb"), selection: $languageIdentifier) {
                Text("한국어").tag(AppLanguage.korean.rawValue)
                Text("English").tag(AppLanguage.english.rawValue)
            }
            .help(appLanguage.localized("ui.choose.the.language.used.in.the.app.interface.16c2f863"))

            Picker(appLanguage.localized("ui.commit.history.time.zone.9e3260bf"), selection: $historyTimeZoneIdentifier) {
                ForEach(AppSettings.historyTimeZones(for: appLanguage), id: \.identifier) { timeZone in
                    Text(timeZone.label).tag(timeZone.identifier)
                }
            }
            .help(appLanguage.localized("ui.choose.the.time.zone.used.for.commit.dates.and.t.ded46b04"))

            Text(appLanguage.localized("ui.the.default.is.korea.standard.time.kst.this.does.02bc8ed0"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(
            width: AppLayout.settingsWindowSize.width,
            height: AppLayout.settingsWindowSize.height
        )
    }
}
