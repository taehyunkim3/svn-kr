import Foundation
import Testing
@testable import SVNMac

/// 소스가 참조하는 문자열 키가 실제 번역 파일에 없으면 화면에 키가 그대로 노출됩니다.
/// 병렬 작업이 리소스 3개 파일에 각각 키를 추가하고 병합하는 과정에서 실제로 발생했던 사고입니다.
@Test func everyReferencedLocalizationKeyExistsInBothLanguages() throws {
    let sources = localizationSourcesDirectory()
    let referenced = try referencedLocalizationKeys(in: sources)
    #expect(!referenced.isEmpty)

    for language in ["ko", "en"] {
        let defined = try definedLocalizationKeys(
            at: sources.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        )
        let missing = referenced.subtracting(defined).sorted()
        #expect(missing.isEmpty, "\(language) 번역 누락: \(missing.joined(separator: ", "))")
    }
}

@Test func koreanAndEnglishDefineTheSameKeysAndFormatSpecifiers() throws {
    let sources = localizationSourcesDirectory()
    let korean = try localizationEntries(
        at: sources.appendingPathComponent("Resources/ko.lproj/Localizable.strings")
    )
    let english = try localizationEntries(
        at: sources.appendingPathComponent("Resources/en.lproj/Localizable.strings")
    )

    let onlyKorean = Set(korean.keys).subtracting(english.keys).sorted()
    let onlyEnglish = Set(english.keys).subtracting(korean.keys).sorted()
    #expect(onlyKorean.isEmpty, "한국어에만 있는 키: \(onlyKorean.joined(separator: ", "))")
    #expect(onlyEnglish.isEmpty, "영어에만 있는 키: \(onlyEnglish.joined(separator: ", "))")

    // 서식 지정자 개수가 다르면 런타임에 문구가 깨지거나 인자가 사라집니다.
    let mismatched = korean.keys
        .filter { key in
            guard let englishValue = english[key] else { return false }
            return formatSpecifierCount(korean[key] ?? "") != formatSpecifierCount(englishValue)
        }
        .sorted()
    #expect(mismatched.isEmpty, "서식 지정자 개수 불일치: \(mismatched.joined(separator: ", "))")
}

private func localizationSourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}

private func referencedLocalizationKeys(in directory: URL) throws -> Set<String> {
    let enumerator = try #require(
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    )
    var keys: Set<String> = []
    let pattern = try NSRegularExpression(pattern: "\"(ui\\.[a-z0-9][a-z0-9._]*)\"")
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let range = NSRange(contents.startIndex..., in: contents)
        for match in pattern.matches(in: contents, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: contents) else { continue }
            keys.insert(String(contents[keyRange]))
        }
    }
    return keys
}

private func localizationEntries(at url: URL) throws -> [String: String] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let pattern = try NSRegularExpression(pattern: "^\"(ui\\.[^\"]+)\"\\s*=\\s*\"(.*)\";$", options: [.anchorsMatchLines])
    let range = NSRange(contents.startIndex..., in: contents)
    var entries: [String: String] = [:]
    for match in pattern.matches(in: contents, range: range) {
        guard let keyRange = Range(match.range(at: 1), in: contents),
              let valueRange = Range(match.range(at: 2), in: contents) else { continue }
        entries[String(contents[keyRange])] = String(contents[valueRange])
    }
    return entries
}

private func definedLocalizationKeys(at url: URL) throws -> Set<String> {
    Set(try localizationEntries(at: url).keys)
}

private func formatSpecifierCount(_ value: String) -> Int {
    guard let pattern = try? NSRegularExpression(pattern: "%\\d+\\$@|%@") else { return 0 }
    return pattern.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value))
}
