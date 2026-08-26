#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 6 else {
    FileHandle.standardError.write(
        Data(
            "usage: dump-localization-call-values.swift <sources> <mapping> <ko.strings> <en.strings> <output>\n".utf8
        )
    )
    exit(2)
}

let sourcesURL = URL(fileURLWithPath: CommandLine.arguments[1])
let mappingURL = URL(fileURLWithPath: CommandLine.arguments[2])
let koreanURL = URL(fileURLWithPath: CommandLine.arguments[3])
let englishURL = URL(fileURLWithPath: CommandLine.arguments[4])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[5])

let mapping = try JSONDecoder().decode(
    [String: String].self,
    from: Data(contentsOf: mappingURL)
)
let rawKeyByExpression = Dictionary(uniqueKeysWithValues: mapping.map { ($0.value, $0.key) })
let korean = try localizationEntries(at: koreanURL)
let english = try localizationEntries(at: englishURL)
let expressions = rawKeyByExpression.keys.sorted { left, right in
    left.count == right.count ? left < right : left.count > right.count
}
let pattern = expressions.map(NSRegularExpression.escapedPattern).joined(separator: "|")
let expressionRegex = try NSRegularExpression(
    pattern: "(?:\(pattern))(?![A-Za-z0-9_])"
)

let sourceFiles = try swiftSourceFiles(at: sourcesURL)
var outputLines: [String] = []
for sourceURL in sourceFiles {
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    var occurrence = 0
    for match in expressionRegex.matches(
        in: source,
        range: NSRange(source.startIndex..., in: source)
    ) {
        guard let expressionRange = Range(match.range, in: source) else { continue }
        let expression = String(source[expressionRange])
        guard let rawKey = rawKeyByExpression[expression],
              let koreanValue = korean[rawKey],
              let englishValue = english[rawKey] else {
            throw DumpError.unresolvedExpression(expression)
        }
        occurrence += 1
        let relativePath = sourceURL.path.replacingOccurrences(
            of: sourcesURL.path + "/",
            with: ""
        )
        outputLines.append(
            [
                relativePath,
                String(occurrence),
                jsonString(koreanValue),
                jsonString(englishValue),
            ].joined(separator: "\t")
        )
    }
}

try (outputLines.joined(separator: "\n") + "\n").write(
    to: outputURL,
    atomically: true,
    encoding: .utf8
)
FileHandle.standardError.write(Data("dumped \(outputLines.count) call sites\n".utf8))

func localizationEntries(at url: URL) throws -> [String: String] {
    let propertyList = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url),
        format: nil
    )
    guard let entries = propertyList as? [String: String] else {
        throw DumpError.invalidStringsFile(url.path)
    }
    return entries
}

func swiftSourceFiles(at rootURL: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw DumpError.unreadableSources(rootURL.path)
    }
    return enumerator.compactMap { item in
        guard let url = item as? URL,
              url.pathExtension == "swift",
              url.lastPathComponent != "LocalizationKey.swift" else {
            return nil
        }
        return url
    }.sorted { $0.path < $1.path }
}

func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    let array = String(decoding: data, as: UTF8.self)
    return String(array.dropFirst().dropLast())
}

enum DumpError: Error, CustomStringConvertible {
    case invalidStringsFile(String)
    case unreadableSources(String)
    case unresolvedExpression(String)

    var description: String {
        switch self {
        case let .invalidStringsFile(path):
            "invalid strings file: \(path)"
        case let .unreadableSources(path):
            "unreadable sources directory: \(path)"
        case let .unresolvedExpression(expression):
            "unresolved localization expression: \(expression)"
        }
    }
}
