import Foundation
import Testing
@testable import SVNMac

@Test func fileHistoryUsesConfiguredTimeZone() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))

    let utc = FileHistoryDatePresentation.string(
        from: date,
        language: .english,
        timeZoneIdentifier: "UTC"
    )
    let seoul = FileHistoryDatePresentation.string(
        from: date,
        language: .english,
        timeZoneIdentifier: "Asia/Seoul"
    )

    #expect(utc.contains("00:00:00.000"))
    #expect(seoul.contains("09:00:00.000 KST"))
    #expect(utc != seoul)
}

@Test func fileHistoryViewWiresConfiguredTimeZone() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("FileHistoryView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("@AppStorage(AppSettings.historyTimeZoneKey)"))
    #expect(source.contains("FileHistoryDatePresentation.string("))
    #expect(!source.contains("date.formatted(date: .numeric, time: .standard)"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
