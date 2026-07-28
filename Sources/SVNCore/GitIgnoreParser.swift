import Foundation

public struct GitIgnoreRule: Identifiable, Hashable, Sendable {
    /// `.gitignore` 파일이 위치한 작업 복사본 상대 디렉터리입니다. 루트는 "."입니다.
    public let sourceDirectory: String
    public let sourceLine: Int
    public let rawPattern: String
    public let pattern: String
    public let isNegated: Bool
    public let isDirectoryOnly: Bool
    public let isRootAnchored: Bool

    public var id: String { "\(sourceDirectory)#\(sourceLine)" }

    public init(
        sourceDirectory: String = ".",
        sourceLine: Int,
        rawPattern: String,
        pattern: String,
        isNegated: Bool,
        isDirectoryOnly: Bool,
        isRootAnchored: Bool
    ) {
        self.sourceDirectory = sourceDirectory
        self.sourceLine = sourceLine
        self.rawPattern = rawPattern
        self.pattern = pattern
        self.isNegated = isNegated
        self.isDirectoryOnly = isDirectoryOnly
        self.isRootAnchored = isRootAnchored
    }
}

public enum GitIgnoreParser {
    /// `sourceDirectory`는 이 `.gitignore` 파일이 위치한 작업 복사본 상대 경로입니다(루트는 ".").
    /// 하위 디렉터리의 `.gitignore`를 여러 번 파싱할 때 규칙이 어느 디렉터리 기준인지 구분하는 데 쓰입니다.
    public static func parse(_ contents: String, sourceDirectory: String = ".") -> [GitIgnoreRule] {
        contents.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, rawLine in
                parseLine(String(rawLine).trimmingCharacters(in: .newlines), number: offset + 1, sourceDirectory: sourceDirectory)
            }
    }

    private static func parseLine(_ source: String, number: Int, sourceDirectory: String) -> GitIgnoreRule? {
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
            sourceDirectory: sourceDirectory,
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
