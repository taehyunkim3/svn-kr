import Foundation

public struct GitIgnoreRule: Identifiable, Hashable, Sendable {
    public let sourceLine: Int
    public let rawPattern: String
    public let pattern: String
    public let isNegated: Bool
    public let isDirectoryOnly: Bool
    public let isRootAnchored: Bool

    public var id: Int { sourceLine }

    public init(
        sourceLine: Int,
        rawPattern: String,
        pattern: String,
        isNegated: Bool,
        isDirectoryOnly: Bool,
        isRootAnchored: Bool
    ) {
        self.sourceLine = sourceLine
        self.rawPattern = rawPattern
        self.pattern = pattern
        self.isNegated = isNegated
        self.isDirectoryOnly = isDirectoryOnly
        self.isRootAnchored = isRootAnchored
    }
}

public enum GitIgnoreParser {
    public static func parse(_ contents: String) -> [GitIgnoreRule] {
        contents.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, rawLine in
                parseLine(String(rawLine).trimmingCharacters(in: .newlines), number: offset + 1)
            }
    }

    private static func parseLine(_ source: String, number: Int) -> GitIgnoreRule? {
        var line = trimmingUnescapedTrailingSpaces(source)
        guard !line.isEmpty else { return nil }
        guard !line.hasPrefix("#") else { return nil }

        let rawPattern = line
        let escapedLeadingMarker = line.hasPrefix("\\#") || line.hasPrefix("\\!")
        var isNegated = false
        if line.hasPrefix("!"), !escapedLeadingMarker {
            isNegated = true
            line.removeFirst()
        }

        let isRootAnchored = line.hasPrefix("/")
        if isRootAnchored { line.removeFirst() }
        let isDirectoryOnly = hasUnescapedTrailingSlash(line)
        if isDirectoryOnly { line.removeLast() }
        line = unescape(line)
        guard !line.isEmpty else { return nil }

        return GitIgnoreRule(
            sourceLine: number,
            rawPattern: rawPattern,
            pattern: line,
            isNegated: isNegated,
            isDirectoryOnly: isDirectoryOnly,
            isRootAnchored: isRootAnchored
        )
    }

    private static func trimmingUnescapedTrailingSpaces(_ value: String) -> String {
        var result = value
        while result.last == " " {
            let slashCount = result.dropLast().reversed().prefix { $0 == "\\" }.count
            if slashCount % 2 == 1 { break }
            result.removeLast()
        }
        return result
    }

    private static func hasUnescapedTrailingSlash(_ value: String) -> Bool {
        guard value.last == "/" else { return false }
        let slashCount = value.dropLast().reversed().prefix { $0 == "\\" }.count
        return slashCount % 2 == 0
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var isEscaping = false
        for character in value {
            if isEscaping {
                result.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }
        if isEscaping { result.append("\\") }
        return result
    }
}
