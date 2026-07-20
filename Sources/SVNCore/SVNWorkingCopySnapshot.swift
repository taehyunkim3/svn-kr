import Foundation

/// SVN이 보존하는 원문 경로와 플랫폼 간 비교에 사용할 NFC 키를 분리합니다.
/// Swift String의 동등성은 정규화 동등 문자열을 같게 취급하므로, 원문 식별은
/// UTF-8 바이트로 수행해야 NFC/NFD가 동시에 존재하는 손상 상태를 찾을 수 있습니다.
public struct SVNPathIdentity: Hashable, Sendable {
    public let rawPath: String
    public let rawUTF8: Data

    public var canonicalKey: String { rawPath.precomposedStringWithCanonicalMapping }
    public var displayPath: String { canonicalKey }

    public init(rawPath: String) {
        self.rawPath = rawPath
        rawUTF8 = Data(rawPath.utf8)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawUTF8 == rhs.rawUTF8 }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawUTF8) }
}

public struct SVNPathCollision: Identifiable, Hashable, Sendable {
    public let canonicalPath: String
    public let rawPaths: [String]
    public let affectedEntryCount: Int
    public let repairableRawPath: String?

    public var id: String { canonicalPath }
    public var displayPath: String { canonicalPath }

    public init(
        canonicalPath: String,
        rawPaths: [String],
        affectedEntryCount: Int,
        repairableRawPath: String? = nil
    ) {
        self.canonicalPath = canonicalPath
        self.rawPaths = rawPaths
        self.affectedEntryCount = affectedEntryCount
        self.repairableRawPath = repairableRawPath
    }
}

/// SVN 관리 경로와 파일 시스템 경로의 정규화 표현만 달라, 하나의 파일 대치로
/// 해석할 수 있는 일대일 후보입니다. 실제 파일 종류와 내용 비교는 SVNClient가
/// 작업 복사본과 BASE 바이트에 접근해 판정합니다.
public struct SVNCanonicalFileReplacement: Hashable, Sendable {
    public let versionedPath: String
    public let localAliasPath: String
    public let revision: String

    public init(versionedPath: String, localAliasPath: String, revision: String) {
        self.versionedPath = versionedPath
        self.localAliasPath = localAliasPath
        self.revision = revision
    }
}

public struct SVNWorkingCopySnapshot: Sendable {
    public let statuses: [SVNStatusEntry]
    public let revision: SVNWorkingCopyRevision
    public let collisions: [SVNPathCollision]
    public let versionedPathsByCanonicalKey: [String: [String]]
    public let canonicalAliasRepairTargets: [String]
    public let canonicalFileReplacements: [SVNCanonicalFileReplacement]

    public var hasPathCollisions: Bool { !collisions.isEmpty }
    public var repairableAliasPaths: [String] {
        collisions.compactMap(\.repairableRawPath)
    }
    public var hasUnrepairablePathCollisions: Bool {
        collisions.contains { $0.repairableRawPath == nil }
    }

    public init(
        statuses: [SVNStatusEntry],
        revision: SVNWorkingCopyRevision,
        collisions: [SVNPathCollision],
        versionedPathsByCanonicalKey: [String: [String]],
        canonicalAliasRepairTargets: [String]? = nil,
        canonicalFileReplacements: [SVNCanonicalFileReplacement] = []
    ) {
        self.statuses = statuses
        self.revision = revision
        self.collisions = collisions
        self.versionedPathsByCanonicalKey = versionedPathsByCanonicalKey
        self.canonicalAliasRepairTargets = canonicalAliasRepairTargets
            ?? collisions.compactMap(\.repairableRawPath)
        self.canonicalFileReplacements = canonicalFileReplacements
    }

    init(entries: [SVNWorkingCopyEntry]) throws {
        let revisions = entries.compactMap(\.revision).compactMap(Int.init).filter { $0 >= 0 }
        guard let minimum = revisions.min(), let maximum = revisions.max() else {
            throw SVNError.malformedResponse
        }
        revision = SVNWorkingCopyRevision(minimum: String(minimum), maximum: String(maximum))

        let versionedEntries = entries.filter { entry in
            guard let revision = entry.revision.flatMap(Int.init), revision >= 0 else { return false }
            return entry.status != "unversioned" && entry.status != "ignored" && entry.status != "external"
        }
        versionedPathsByCanonicalKey = Dictionary(grouping: versionedEntries, by: { canonicalKey($0.path) })
            .mapValues { distinctRawPaths($0.map(\.path)) }

        let ambiguousVersionedCollisions = versionedPathsByCanonicalKey.compactMap { key, paths -> SVNPathCollision? in
            guard paths.count > 1 else { return nil }
            return SVNPathCollision(canonicalPath: key, rawPaths: paths, affectedEntryCount: paths.count)
        }

        let orphanedRoots = Self.orphanedAdditionRoots(
            entries: entries,
            versionedPathsByCanonicalKey: versionedPathsByCanonicalKey
        )
        let orphanedCollisions = orphanedRoots.map { root in
            let affected = entries.filter { entry in
                Self.isAtOrBelow(canonicalKey(entry.path), root: root.canonicalPath)
                    && Self.isCanonicalAliasSchedulingNode(entry)
            }
            return SVNPathCollision(
                canonicalPath: root.canonicalPath,
                rawPaths: distinctRawPaths(root.rawPaths + affected.map(\.path)),
                affectedEntryCount: affected.count,
                repairableRawPath: root.repairableRawPath
            )
        }

        collisions = Self.mergeCollisions(ambiguousVersionedCollisions + orphanedCollisions)
        canonicalAliasRepairTargets = Self.canonicalAliasRepairTargets(
            entries: entries,
            rawRoots: collisions.compactMap(\.repairableRawPath)
        )
        canonicalFileReplacements = Self.canonicalFileReplacements(
            entries: entries,
            versionedPathsByCanonicalKey: versionedPathsByCanonicalKey
        )
        statuses = Self.visibleStatuses(
            from: entries,
            orphanedRoots: orphanedRoots.map(\.canonicalPath),
            versionedPathsByCanonicalKey: versionedPathsByCanonicalKey
        )
    }

    /// 새 로컬 경로를 가장 가까운 기존 SVN 상위 경로의 정확한 원문에 연결합니다.
    /// 기존 경로가 정규화 기준으로 둘 이상이면 안전하게 결정할 수 없어 nil입니다.
    public func resolvedPath(for rawPath: String) -> String? {
        let canonicalPath = canonicalKey(rawPath)
        if let exact = versionedPathsByCanonicalKey[canonicalPath] {
            return exact.count == 1 ? exact[0] : nil
        }

        let components = pathComponents(rawPath)
        guard !components.isEmpty else { return canonicalPath }
        for prefixLength in stride(from: components.count - 1, through: 1, by: -1) {
            let prefix = components.prefix(prefixLength).joined(separator: "/")
            guard let ancestors = versionedPathsByCanonicalKey[canonicalKey(prefix)] else { continue }
            guard ancestors.count == 1 else { return nil }
            let suffix = components.dropFirst(prefixLength)
                .joined(separator: "/")
            return suffix.isEmpty ? ancestors[0] : ancestors[0] + "/" + suffix
        }
        return canonicalPath
    }

    func resolvingCanonicalFileReplacements(
        modifiedPaths: Set<String>,
        unchangedPaths: Set<String>
    ) -> SVNWorkingCopySnapshot {
        let resolvedStatuses = statuses.compactMap { entry -> SVNStatusEntry? in
            if unchangedPaths.contains(entry.path) { return nil }
            if modifiedPaths.contains(entry.path) {
                return SVNStatusEntry(path: entry.path, item: .modified, revision: entry.revision)
            }
            return entry
        }
        return SVNWorkingCopySnapshot(
            statuses: resolvedStatuses,
            revision: revision,
            collisions: collisions,
            versionedPathsByCanonicalKey: versionedPathsByCanonicalKey,
            canonicalAliasRepairTargets: canonicalAliasRepairTargets,
            canonicalFileReplacements: canonicalFileReplacements
        )
    }

    private struct OrphanedRoot {
        let canonicalPath: String
        let rawPaths: [String]
        let repairableRawPath: String?
    }

    private static func orphanedAdditionRoots(
        entries: [SVNWorkingCopyEntry],
        versionedPathsByCanonicalKey: [String: [String]]
    ) -> [OrphanedRoot] {
        let candidates = entries.compactMap { entry -> OrphanedRoot? in
            guard isMissingScheduledAddition(entry) else { return nil }
            let key = canonicalKey(entry.path)
            guard let versionedPaths = versionedPathsByCanonicalKey[key], !versionedPaths.isEmpty else { return nil }
            guard versionedPaths.contains(where: { Data($0.utf8) != Data(entry.path.utf8) }) else { return nil }
            return OrphanedRoot(
                canonicalPath: key,
                rawPaths: versionedPaths + [entry.path],
                repairableRawPath: versionedPaths.count == 1 ? entry.path : nil
            )
        }
        .sorted { pathComponents($0.canonicalPath).count < pathComponents($1.canonicalPath).count }

        var roots: [OrphanedRoot] = []
        for candidate in candidates where !roots.contains(where: { isAtOrBelow(candidate.canonicalPath, root: $0.canonicalPath) }) {
            roots.append(candidate)
        }
        return roots
    }

    private static func visibleStatuses(
        from entries: [SVNWorkingCopyEntry],
        orphanedRoots: [String],
        versionedPathsByCanonicalKey: [String: [String]]
    ) -> [SVNStatusEntry] {
        let changed = entries.filter { entry in
            entry.status != "normal" && entry.status != "external" && entry.status != "ignored"
        }
        let filtered = changed.filter { entry in
            let key = canonicalKey(entry.path)
            if isMissingScheduledAddition(entry), orphanedRoots.contains(where: { isAtOrBelow(key, root: $0) }) {
                return false
            }
            if entry.status == "unversioned", versionedPathsByCanonicalKey[key]?.isEmpty == false {
                return false
            }
            return true
        }

        let groups = Dictionary(grouping: filtered, by: { canonicalKey($0.path) })
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key] else { return nil }
            let preferred = group.first(where: { entry in
                entry.revision.flatMap(Int.init).map { $0 >= 0 } == true && entry.status != "missing"
            }) ?? group.first
            guard let preferred else { return nil }
            let resolved: String
            if let exact = versionedPathsByCanonicalKey[key], exact.count == 1 {
                resolved = exact[0]
            } else {
                resolved = resolveNewPath(
                    preferred.path,
                    versionedPathsByCanonicalKey: versionedPathsByCanonicalKey
                ) ?? key
            }
            return SVNStatusEntry(
                path: resolved,
                item: SVNStatusKind(rawValue: preferred.status),
                revision: preferred.revision
            )
        }
    }

    private static func resolveNewPath(
        _ rawPath: String,
        versionedPathsByCanonicalKey: [String: [String]]
    ) -> String? {
        let components = pathComponents(rawPath)
        guard !components.isEmpty else { return canonicalKey(rawPath) }
        for prefixLength in stride(from: components.count - 1, through: 1, by: -1) {
            let prefix = components.prefix(prefixLength).joined(separator: "/")
            guard let ancestors = versionedPathsByCanonicalKey[canonicalKey(prefix)] else { continue }
            guard ancestors.count == 1 else { return nil }
            let suffix = components.dropFirst(prefixLength)
                .joined(separator: "/")
            return ancestors[0] + "/" + suffix
        }
        return canonicalKey(rawPath)
    }

    private static func isMissingScheduledAddition(_ entry: SVNWorkingCopyEntry) -> Bool {
        entry.status == "missing" && (entry.revision == nil || entry.revision == "-1")
    }

    private static func isCanonicalAliasSchedulingNode(_ entry: SVNWorkingCopyEntry) -> Bool {
        (entry.status == "missing" || entry.status == "added")
            && (entry.revision == nil || entry.revision == "-1")
    }

    private static func canonicalAliasRepairTargets(
        entries: [SVNWorkingCopyEntry],
        rawRoots: [String]
    ) -> [String] {
        distinctRawPaths(entries.compactMap { entry in
            guard isCanonicalAliasSchedulingNode(entry),
                  rawRoots.contains(where: { isRawAtOrBelow(entry.path, root: $0) }) else {
                return nil
            }
            return entry.path
        })
        .sorted { lhs, rhs in
            let lhsDepth = pathComponents(lhs).count
            let rhsDepth = pathComponents(rhs).count
            if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
            return Data(lhs.utf8).lexicographicallyPrecedes(Data(rhs.utf8))
        }
    }

    private static func canonicalFileReplacements(
        entries: [SVNWorkingCopyEntry],
        versionedPathsByCanonicalKey: [String: [String]]
    ) -> [SVNCanonicalFileReplacement] {
        let entriesByKey = Dictionary(grouping: entries, by: { canonicalKey($0.path) })
        return entriesByKey.keys
            .sorted()
            .compactMap { key in
                guard versionedPathsByCanonicalKey[key]?.count == 1,
                      let group = entriesByKey[key] else {
                    return nil
                }
                let missing = group.filter {
                    $0.status == "missing" && $0.revision.flatMap(Int.init).map { $0 >= 0 } == true
                }
                let aliases = distinctRawPaths(group.filter { $0.status == "unversioned" }.map(\.path))
                guard missing.count == 1,
                      aliases.count == 1,
                      let revision = missing[0].revision,
                      Data(missing[0].path.utf8) != Data(aliases[0].utf8) else {
                    return nil
                }
                return SVNCanonicalFileReplacement(
                    versionedPath: missing[0].path,
                    localAliasPath: aliases[0],
                    revision: revision
                )
            }
    }

    private static func mergeCollisions(_ collisions: [SVNPathCollision]) -> [SVNPathCollision] {
        Dictionary(grouping: collisions, by: \.canonicalPath)
            .map { key, values in
                SVNPathCollision(
                    canonicalPath: key,
                    rawPaths: distinctRawPaths(values.flatMap(\.rawPaths)),
                    affectedEntryCount: values.map(\.affectedEntryCount).max() ?? 0,
                    repairableRawPath: values.count == 1 ? values[0].repairableRawPath : nil
                )
            }
            .sorted { $0.canonicalPath < $1.canonicalPath }
    }

    private static func isAtOrBelow(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private static func isRawAtOrBelow(_ path: String, root: String) -> Bool {
        let pathBytes = Data(path.utf8)
        let rootBytes = Data(root.utf8)
        return pathBytes == rootBytes || pathBytes.starts(with: rootBytes + Data([0x2F]))
    }
}

private func canonicalKey(_ path: String) -> String {
    path.precomposedStringWithCanonicalMapping
}

private func pathComponents(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
}

private func distinctRawPaths(_ paths: [String]) -> [String] {
    var seen: Set<Data> = []
    return paths.filter { seen.insert(Data($0.utf8)).inserted }
        .sorted { Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8)) }
}
