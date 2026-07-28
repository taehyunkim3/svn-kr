import Foundation

final class HistoryDateFormatting: @unchecked Sendable {
    static let shared = HistoryDateFormatting()

    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func string(
        from date: Date,
        language: AppLanguage,
        timeZone: TimeZone,
        usesKSTAbbreviation: Bool
    ) -> String {
        lock.withLock {
            let key = "\(language.rawValue)|\(timeZone.identifier)"
            let formatter = formatters[key] ?? {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: language == .english ? "en_US_POSIX" : "ko_KR")
                formatter.timeZone = timeZone
                formatter.dateFormat = "yyyy-MM-dd (EEE) HH:mm:ss.SSS"
                formatters[key] = formatter
                return formatter
            }()
            let abbreviation = usesKSTAbbreviation
                ? "KST"
                : (timeZone.abbreviation(for: date) ?? timeZone.identifier)
            return "\(formatter.string(from: date)) \(abbreviation)"
        }
    }
}
