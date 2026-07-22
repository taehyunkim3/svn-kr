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
            ("Asia/Seoul", language.text("한국 표준시 (KST, UTC+9)", "Korea Standard Time (KST, UTC+9)")),
            (systemHistoryTimeZone, language.text("Mac 시스템 시간대 (\(TimeZone.current.identifier))", "Mac system time zone (\(TimeZone.current.identifier))")),
            ("UTC", language.text("협정 세계시 (UTC)", "Coordinated Universal Time (UTC)")),
            ("Asia/Tokyo", language.text("일본 표준시 (JST, UTC+9)", "Japan Standard Time (JST, UTC+9)")),
            ("America/Los_Angeles", language.text("미국 태평양 시간", "US Pacific Time")),
            ("America/New_York", language.text("미국 동부 시간", "US Eastern Time")),
            ("Europe/London", language.text("영국 시간", "UK Time")),
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

    func text(_ korean: String, _ english: String) -> String {
        // 현재 앱은 두 언어만 지원하므로 간단한 쌍을 사용합니다. 상태 모델에는
        // 번역 결과를 저장하지 않고 화면을 그릴 때 이 메서드로 선택합니다.
        self == .english ? english : korean
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
            Picker(appLanguage.text("언어", "Language"), selection: $languageIdentifier) {
                Text("한국어").tag(AppLanguage.korean.rawValue)
                Text("English").tag(AppLanguage.english.rawValue)
            }
            .help(appLanguage.text("앱 화면에 사용할 언어를 선택합니다.", "Choose the language used in the app interface."))

            Picker(appLanguage.text("커밋 기록 시간대", "Commit history time zone"), selection: $historyTimeZoneIdentifier) {
                ForEach(AppSettings.historyTimeZones(for: appLanguage), id: \.identifier) { timeZone in
                    Text(timeZone.label).tag(timeZone.identifier)
                }
            }
            .help(appLanguage.text("커밋 기록의 날짜와 시간을 표시할 기준 시간대를 선택합니다.", "Choose the time zone used for commit dates and times."))

            Text(appLanguage.text("기본값은 한국 표준시(KST)이며 커밋 원본 시각은 변경하지 않습니다.", "The default is Korea Standard Time (KST). This does not change the original commit time."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 230)
    }
}
