#!/usr/bin/env swift

import Foundation

private struct StringCatalog: Decodable {
    let strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {}

private struct KeyDefinition {
    let rawValue: String
    let topLevelName: String
    let groupName: String
    let memberName: String

    var expression: String {
        ".\(topLevelName).\(groupName).\(memberName)"
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
private let definitions = try catalog.strings.keys.map { key in
    try makeDefinition(key: key)
}.sorted { $0.rawValue < $1.rawValue }

try validateUniqueExpressions(definitions)

let source = renderSource(definitions)
try source.write(to: outputURL, atomically: true, encoding: .utf8)

if let mappingURL {
    let mapping = Dictionary(uniqueKeysWithValues: definitions.map { ($0.rawValue, $0.expression) })
    let data = try JSONSerialization.data(withJSONObject: mapping, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: mappingURL, options: .atomic)
}

private func makeDefinition(key: String) throws -> KeyDefinition {
    let components = key.split(separator: ".").map(String.init)
    guard components.count == 3 else {
        throw GenerationError.invalidKey(key)
    }
    let identifiers = try components.map { try identifier(from: $0, key: key) }
    return KeyDefinition(
        rawValue: key,
        topLevelName: identifiers[0],
        groupName: identifiers[1],
        memberName: identifiers[2]
    )
}

private func identifier(from component: String, key: String) throws -> String {
    guard let first = component.first,
          first.isLetter || first == "_",
          component.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
          !swiftKeywords.contains(component) else {
        throw GenerationError.invalidKey(key)
    }
    return component
}

private func upperCamelCase(_ identifier: String) -> String {
    if identifier == "ui" { return "UI" }
    guard let first = identifier.first else { return "" }
    return first.uppercased() + identifier.dropFirst()
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
        lines.append("    static let \(topLevel) = Localization\(upperCamelCase(topLevel))Keys()")
    }
    lines.append("")
    lines.append("    static let allCases: [LocalizationKey] = \"\"\"")
    for definition in definitions {
        lines.append("        \(definition.rawValue)")
    }
    lines.append("        \"\"\"")
    lines.append("        .split(separator: \"\\n\")")
    lines.append("        .map { LocalizationKey(String($0)) }")
    lines.append("}")

    for topLevel in topLevels.keys.sorted() {
        let topLevelDefinitions = topLevels[topLevel, default: []]
        lines.append("")
        lines.append("struct Localization\(upperCamelCase(topLevel))Keys {")
        let groups = Dictionary(grouping: topLevelDefinitions, by: \.groupName)
        for group in groups.keys.sorted() {
            lines.append(
                "    let \(group) = Localization\(upperCamelCase(topLevel))\(upperCamelCase(group))Keys()"
            )
        }
        lines.append("}")

        for group in groups.keys.sorted() {
            lines.append("")
            lines.append(
                "struct Localization\(upperCamelCase(topLevel))\(upperCamelCase(group))Keys {"
            )
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
