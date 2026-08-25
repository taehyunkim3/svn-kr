import Foundation
import Testing
@testable import SVNMac

@Test func generatedLocalizationKeysMatchEveryLocalizationResource() throws {
    let sources = localizationSourcesDirectory()
    let generatedKeys = Set(LocalizationKey.allCases.map(\.rawValue))
    #expect(!generatedKeys.isEmpty)
    #expect(generatedKeys.count == LocalizationKey.allCases.count, "생성 타입에 중복 키가 있습니다")

    let catalogKeys = try catalogLocalizationKeys(
        at: sources.appendingPathComponent("Resources/Localizable.xcstrings")
    )
    #expect(generatedKeys == catalogKeys, "String Catalog와 생성 타입의 키가 다릅니다")

    for language in ["ko", "en"] {
        let defined = try definedLocalizationKeys(
            at: sources.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        )
        let missing = generatedKeys.subtracting(defined).sorted()
        let untyped = defined.subtracting(generatedKeys).sorted()
        #expect(missing.isEmpty, "\(language) 번역 누락: \(missing.joined(separator: ", "))")
        #expect(untyped.isEmpty, "\(language) 타입 누락: \(untyped.joined(separator: ", "))")
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

private func catalogLocalizationKeys(at url: URL) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let catalog = try #require(object as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: Any])
    return Set(strings.keys)
}

private func localizationEntries(at url: URL) throws -> [String: String] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let pattern = try NSRegularExpression(pattern: "^\"([^\"]+)\"\\s*=\\s*\"(.*)\";$", options: [.anchorsMatchLines])
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
