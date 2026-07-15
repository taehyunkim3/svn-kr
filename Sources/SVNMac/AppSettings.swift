import Foundation
import SwiftUI

enum AppSettings {
    static let historyTimeZoneKey = "history-time-zone"
    static let defaultHistoryTimeZone = "Asia/Seoul"
    static let systemHistoryTimeZone = "__system__"

    static let historyTimeZones: [(identifier: String, label: String)] = [
        ("Asia/Seoul", "한국 표준시 (KST, UTC+9)"),
        (systemHistoryTimeZone, "Mac 시스템 시간대 (\(TimeZone.current.identifier))"),
        ("UTC", "협정 세계시 (UTC)"),
        ("Asia/Tokyo", "일본 표준시 (JST, UTC+9)"),
        ("America/Los_Angeles", "미국 태평양 시간"),
        ("America/New_York", "미국 동부 시간"),
        ("Europe/London", "영국 시간"),
    ].reduce(into: []) { result, item in
        if !result.contains(where: { $0.identifier == item.0 }) {
            result.append((identifier: item.0, label: item.1))
        }
    }
}

struct AppSettingsView: View {
    @AppStorage(AppSettings.historyTimeZoneKey)
    private var historyTimeZoneIdentifier = AppSettings.defaultHistoryTimeZone

    var body: some View {
        Form {
            Picker("커밋 기록 시간대", selection: $historyTimeZoneIdentifier) {
                ForEach(AppSettings.historyTimeZones, id: \.identifier) { timeZone in
                    Text(timeZone.label).tag(timeZone.identifier)
                }
            }
            .help("커밋 기록의 날짜와 시간을 표시할 기준 시간대를 선택합니다.")

            Text("기본값은 한국 표준시(KST)이며 커밋 원본 시각은 변경하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 180)
    }
}
