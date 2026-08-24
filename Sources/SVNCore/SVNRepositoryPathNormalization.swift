import Foundation

public struct SVNRepositoryPathNormalizationTarget: Sendable, Hashable, Identifiable {
    public let repositoryPath: String
    public let normalizedPath: String
    public let isDirectory: Bool

    public var id: String { repositoryPath }

    public init(repositoryPath: String, normalizedPath: String, isDirectory: Bool) {
        self.repositoryPath = repositoryPath
        self.normalizedPath = normalizedPath
        self.isDirectory = isDirectory
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        Data(lhs.repositoryPath.utf8) == Data(rhs.repositoryPath.utf8)
            && Data(lhs.normalizedPath.utf8) == Data(rhs.normalizedPath.utf8)
            && lhs.isDirectory == rhs.isDirectory
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Data(repositoryPath.utf8))
        hasher.combine(Data(normalizedPath.utf8))
        hasher.combine(isDirectory)
    }
}

public struct SVNRepositoryPathNormalizationResult: Sendable {
    public let renamedTargets: [SVNRepositoryPathNormalizationTarget]
    public let skippedTargets: [SVNRepositoryPathNormalizationTarget]
    public let committedRevisions: [String]

    public init(
        renamedTargets: [SVNRepositoryPathNormalizationTarget],
        skippedTargets: [SVNRepositoryPathNormalizationTarget],
        committedRevisions: [String]
    ) {
        self.renamedTargets = renamedTargets
        self.skippedTargets = skippedTargets
        self.committedRevisions = committedRevisions
    }
}

public enum SVNRepositoryPathNormalizationError: Error, Sendable {
    case blockedByLocalChanges(paths: [String])
    case blockedByLocks(paths: [String])
    case invalidTargets(paths: [String])
    case failed(
        result: SVNRepositoryPathNormalizationResult,
        failedTarget: SVNRepositoryPathNormalizationTarget,
        details: String
    )
}

struct SVNRepositoryListEntry: Sendable {
    let path: String
    let isDirectory: Bool
}

enum SVNRepositoryPathNormalization {
    static func targets(
        from entries: [SVNRepositoryListEntry]
    ) -> [SVNRepositoryPathNormalizationTarget] {
        let candidates = entries.compactMap { entry -> SVNRepositoryPathNormalizationTarget? in
            let components = rawComponents(entry.path)
            guard let lastComponent = components.last else { return nil }
            let normalizedLastComponent = lastComponent.precomposedStringWithCanonicalMapping
            guard Data(lastComponent.utf8) != Data(normalizedLastComponent.utf8) else {
                return nil
            }
            let normalized = (components.dropLast() + [normalizedLastComponent])
                .joined(separator: "/")
            return SVNRepositoryPathNormalizationTarget(
                repositoryPath: entry.path,
                normalizedPath: normalized,
                isDirectory: entry.isDirectory
            )
        }
        return minimalTargets(candidates)
    }

    static func minimalTargets(
        _ targets: [SVNRepositoryPathNormalizationTarget]
    ) -> [SVNRepositoryPathNormalizationTarget] {
        let ordered = targets.enumerated().sorted { lhs, rhs in
            let lhsComponents = rawComponents(lhs.element.repositoryPath)
            let rhsComponents = rawComponents(rhs.element.repositoryPath)
            if lhsComponents.count != rhsComponents.count {
                return lhsComponents.count < rhsComponents.count
            }
            let lhsBytes = Data(lhs.element.repositoryPath.utf8)
            let rhsBytes = Data(rhs.element.repositoryPath.utf8)
            if lhsBytes != rhsBytes {
                return lhsBytes.lexicographicallyPrecedes(rhsBytes)
            }
            return lhs.offset < rhs.offset
        }

        var selected: [SVNRepositoryPathNormalizationTarget] = []
        var selectedPathBytes: Set<Data> = []
        for (_, target) in ordered {
            let pathBytes = Data(target.repositoryPath.utf8)
            guard selectedPathBytes.insert(pathBytes).inserted else { continue }
            selected.append(target)
        }
        return selected
    }

    static func isValidTarget(_ target: SVNRepositoryPathNormalizationTarget) -> Bool {
        let repositoryComponents = rawComponents(target.repositoryPath)
        let normalizedComponents = rawComponents(target.normalizedPath)
        guard repositoryComponents.count == normalizedComponents.count,
              let repositoryLastComponent = repositoryComponents.last,
              let normalizedLastComponent = normalizedComponents.last else {
            return false
        }

        let expectedLastComponent = repositoryLastComponent.precomposedStringWithCanonicalMapping
        guard Data(repositoryLastComponent.utf8) != Data(expectedLastComponent.utf8),
              Data(normalizedLastComponent.utf8) == Data(expectedLastComponent.utf8) else {
            return false
        }

        return zip(repositoryComponents.dropLast(), normalizedComponents.dropLast()).allSatisfy {
            Data($0.utf8) == Data($1.utf8)
        }
    }

    static func isAtOrBelowCanonicalPath(_ path: String, root: String) -> Bool {
        let pathComponents = canonicalComponentBytes(path)
        let rootComponents = canonicalComponentBytes(root)
        guard pathComponents.count >= rootComponents.count else { return false }
        return zip(pathComponents, rootComponents).allSatisfy(==)
    }

    static func replacingRawPrefix(
        in path: String,
        sourcePrefix: String,
        destinationPrefix: String
    ) -> String {
        let pathComponents = rawComponents(path)
        let sourceComponents = rawComponents(sourcePrefix)
        guard pathComponents.count >= sourceComponents.count,
              zip(pathComponents, sourceComponents).allSatisfy({
                  Data($0.0.utf8) == Data($0.1.utf8)
              }) else {
            return path
        }
        return (rawComponents(destinationPrefix) + pathComponents.dropFirst(sourceComponents.count))
            .joined(separator: "/")
    }

    static func repositoryURL(_ baseURL: String, appending path: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let encodedPath = rawComponents(path).map(percentEncodePathComponent).joined(separator: "/")
        return encodedPath.isEmpty ? base : base + "/" + encodedPath
    }

    static func committedRevision(from output: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"Committed revision ([0-9]+)\."#
        ) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              let revisionRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[revisionRange])
    }

    private static func rawComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func canonicalComponentBytes(_ path: String) -> [Data] {
        rawComponents(path).map {
            Data($0.precomposedStringWithCanonicalMapping.utf8)
        }
    }

    private static func percentEncodePathComponent(_ component: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(component.utf8.count * 3)
        for byte in component.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E:
                encoded.unicodeScalars.append(UnicodeScalar(byte))
            default:
                encoded += String(format: "%%%02X", byte)
            }
        }
        return encoded
    }
}
