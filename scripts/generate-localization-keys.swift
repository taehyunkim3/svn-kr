#!/usr/bin/env swift

import Foundation

private struct StringCatalog: Decodable {
    let strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {
    let localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Decodable {
    let value: String
}

private struct KeyDefinition {
    let rawValue: String
    let topLevelName: String
    let groupName: String?
    let baseMemberName: String
    let englishValue: String
    var memberName: String

    var expression: String {
        if let groupName {
            ".\(topLevelName).\(groupName).\(memberName)"
        } else {
            ".\(topLevelName).\(memberName)"
        }
    }
}

private let swiftKeywords: Set<String> = [
    "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer",
    "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
    "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
    "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return",
    "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
    "typealias", "var", "where", "while",
]

private let catalogURL: URL
private let outputURL: URL
private let mappingURL: URL?

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(
        Data("usage: generate-localization-keys.swift <catalog> <output> [mapping]\n".utf8)
    )
    exit(2)
}

catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
mappingURL = CommandLine.arguments.count == 4
    ? URL(fileURLWithPath: CommandLine.arguments[3])
    : nil

private let catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: catalogURL))
private var definitions = try catalog.strings.map { key, entry in
    try makeDefinition(key: key, entry: entry)
}.sorted { $0.rawValue < $1.rawValue }

resolveMemberNameCollisions(in: &definitions)
try validateUniqueExpressions(definitions)

let source = renderSource(definitions)
try source.write(to: outputURL, atomically: true, encoding: .utf8)

if let mappingURL {
    let mapping = Dictionary(uniqueKeysWithValues: definitions.map { ($0.rawValue, $0.expression) })
    let data = try JSONSerialization.data(withJSONObject: mapping, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: mappingURL, options: .atomic)
}

private func makeDefinition(key: String, entry: CatalogEntry) throws -> KeyDefinition {
    var components = key.split(separator: ".").map(String.init)
    if let last = components.last,
       last.count == 8,
       last.allSatisfy({ $0.isHexDigit }) {
        components.removeLast()
    }
    guard let topLevel = components.first else {
        throw GenerationError.invalidKey(key)
    }

    let topLevelName = identifier(from: [topLevel])
    let remaining = Array(components.dropFirst())
    let groupName: String?
    let memberComponents: [String]
    if topLevel == "ui", let first = remaining.first {
        groupName = identifier(from: [first])
        memberComponents = Array(remaining.dropFirst())
    } else {
        groupName = nil
        memberComponents = remaining
    }
    let baseMemberName = memberComponents.isEmpty ? "label" : identifier(from: memberComponents)
    let englishValue = entry.localizations?["en"]?.stringUnit?.value ?? ""
    return KeyDefinition(
        rawValue: key,
        topLevelName: topLevelName,
        groupName: groupName,
        baseMemberName: baseMemberName,
        englishValue: englishValue,
        memberName: baseMemberName
    )
}

private func resolveMemberNameCollisions(in definitions: inout [KeyDefinition]) {
    let groupedIndices = Dictionary(grouping: definitions.indices) { index in
        let definition = definitions[index]
        return [
            definition.topLevelName,
            definition.groupName ?? "",
            definition.baseMemberName,
        ].joined(separator: "\u{0}")
    }

    for indices in groupedIndices.values where indices.count > 1 {
        let sortedIndices = indices.sorted { definitions[$0].rawValue < definitions[$1].rawValue }
        let englishValues = sortedIndices.map { definitions[$0].englishValue }
        var usedNames: Set<String> = []
        for (offset, index) in sortedIndices.enumerated() {
            let suffix = collisionSuffix(
                for: definitions[index].englishValue,
                comparedWith: englishValues,
                fallbackIndex: offset
            )
            var memberName = definitions[index].baseMemberName + suffix
            var duplicateIndex = 2
            while usedNames.contains(memberName) {
                memberName = definitions[index].baseMemberName + suffix + String(duplicateIndex)
                duplicateIndex += 1
            }
            definitions[index].memberName = memberName
            usedNames.insert(memberName)
        }
    }
}

private func collisionSuffix(
    for value: String,
    comparedWith values: [String],
    fallbackIndex: Int
) -> String {
    if value.hasSuffix("?") {
        return "Question"
    }
    if value.hasSuffix("…") || value.hasSuffix("...") {
        return "Action"
    }
    if value.contains("%") {
        return "Formatted"
    }

    let words = identifierWords(in: value)
    let otherWords = Set(values.filter { $0 != value }.flatMap(identifierWords))
    let uniqueWords = words.filter { !otherWords.contains($0) }
    if !uniqueWords.isEmpty {
        return upperCamelCase(Array(uniqueWords.prefix(4)))
    }
    return fallbackIndex == 0 ? "Primary" : "Secondary"
}

private func identifierWords(in value: String) -> [String] {
    value.lowercased()
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { !["a", "an", "and", "are", "is", "the", "to", "your"].contains($0) }
}

private func identifier(from components: [String]) -> String {
    let words = components.flatMap { component in
        component.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    guard let first = words.first else { return "label" }
    let value = first.lowercased() + upperCamelCase(Array(words.dropFirst()))
    if swiftKeywords.contains(value) || value.first?.isNumber == true {
        return "localization" + upperCamelCase([value])
    }
    return value
}

private func upperCamelCase(_ words: [String]) -> String {
    words.map { word in
        guard let first = word.first else { return "" }
        return first.uppercased() + word.dropFirst().lowercased()
    }.joined()
}

private func validateUniqueExpressions(_ definitions: [KeyDefinition]) throws {
    let grouped = Dictionary(grouping: definitions, by: \.expression)
    let duplicates = grouped.filter { $0.value.count > 1 }.keys.sorted()
    guard duplicates.isEmpty else {
        throw GenerationError.duplicateExpressions(duplicates)
    }
}

private func renderSource(_ definitions: [KeyDefinition]) -> String {
    let topLevels = Dictionary(grouping: definitions, by: \.topLevelName)
    var lines = [
        "struct LocalizationKey: Hashable, Sendable {",
        "    let rawValue: String",
        "",
        "    fileprivate init(_ rawValue: String) {",
        "        self.rawValue = rawValue",
        "    }",
        "",
    ]

    for topLevel in topLevels.keys.sorted() {
        lines.append("    static let \(topLevel) = Localization\(upperCamelCase([topLevel]))Keys()")
    }
    lines.append("")
    lines.append("    static let allCases: [LocalizationKey] = [")
    for definition in definitions {
        lines.append("        \(definition.expression),")
    }
    lines.append("    ]")
    lines.append("}")

    for topLevel in topLevels.keys.sorted() {
        let topLevelDefinitions = topLevels[topLevel, default: []]
        lines.append("")
        lines.append("struct Localization\(upperCamelCase([topLevel]))Keys {")
        if topLevel == "ui" {
            let groups = Dictionary(grouping: topLevelDefinitions) { $0.groupName ?? "label" }
            for group in groups.keys.sorted() {
                lines.append(
                    "    let \(group) = LocalizationUI\(upperCamelCase([group]))Keys()"
                )
            }
        } else {
            for definition in topLevelDefinitions.sorted(by: { $0.memberName < $1.memberName }) {
                lines.append(
                    "    let \(definition.memberName) = LocalizationKey(\"\(definition.rawValue)\")"
                )
            }
        }
        lines.append("}")

        guard topLevel == "ui" else { continue }
        let groups = Dictionary(grouping: topLevelDefinitions) { $0.groupName ?? "label" }
        for group in groups.keys.sorted() {
            lines.append("")
            lines.append("struct LocalizationUI\(upperCamelCase([group]))Keys {")
            for definition in groups[group, default: []].sorted(by: { $0.memberName < $1.memberName }) {
                lines.append(
                    "    let \(definition.memberName) = LocalizationKey(\"\(definition.rawValue)\")"
                )
            }
            lines.append("}")
        }
    }

    lines.append("")
    return lines.joined(separator: "\n")
}

private enum GenerationError: Error, CustomStringConvertible {
    case duplicateExpressions([String])
    case invalidKey(String)

    var description: String {
        switch self {
        case let .duplicateExpressions(expressions):
            "duplicate generated expressions: \(expressions.joined(separator: ", "))"
        case let .invalidKey(key):
            "invalid localization key: \(key)"
        }
    }
}
