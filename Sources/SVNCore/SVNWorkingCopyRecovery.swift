import Foundation

public struct SVNRecoveryPathMapping: Sendable {
    public let sourcePath: String
    public let destinationPath: String
    public let status: SVNStatusKind

    public init(sourcePath: String, destinationPath: String, status: SVNStatusKind) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.status = status
    }
}

public struct SVNRecoveryPreview: Sendable {
    public let mappings: [SVNRecoveryPathMapping]
    public let ignoredAliasCount: Int
    public let blockingPaths: [String]

    public var modifiedCount: Int {
        mappings.count { $0.status == .modified || $0.status == .replaced }
    }

    public var addedCount: Int {
        mappings.count { $0.status == .added || $0.status == .unversioned }
    }

    public var deletedCount: Int {
        mappings.count { $0.status == .deleted || $0.status == .missing }
    }

    public init(
        mappings: [SVNRecoveryPathMapping],
        ignoredAliasCount: Int,
        blockingPaths: [String]
    ) {
        self.mappings = mappings
        self.ignoredAliasCount = ignoredAliasCount
        self.blockingPaths = blockingPaths
    }
}

public struct SVNRecoveryResult: Sendable {
    public let destinationPath: String
    public let snapshot: SVNWorkingCopySnapshot
    public let migratedPaths: [String]

    public init(destinationPath: String, snapshot: SVNWorkingCopySnapshot, migratedPaths: [String]) {
        self.destinationPath = destinationPath
        self.snapshot = snapshot
        self.migratedPaths = migratedPaths
    }
}

enum SVNWorkingCopyRecovery {
    static func preview(
        sourcePath: String,
        snapshot: SVNWorkingCopySnapshot,
        fileManager: FileManager = .default
    ) -> SVNRecoveryPreview {
        let sourceRoot = URL(fileURLWithPath: sourcePath, isDirectory: true).standardizedFileURL
        var blockers = snapshot.collisions.compactMap { collision -> String? in
            guard snapshot.versionedPathsByCanonicalKey[collision.canonicalPath]?.count ?? 0 > 1 else {
                return nil
            }
            return collision.displayPath
        }

        let mappings = snapshot.statuses.compactMap { entry -> SVNRecoveryPathMapping? in
            guard entry.isSelectableForCommit || entry.item == .missing || entry.item == .conflicted else { return nil }
            let destination = entry.path.precomposedStringWithCanonicalMapping
            guard isSafeRelativePath(destination) else {
                blockers.append(destination)
                return nil
            }

            // 복구는 파일 내용만 옮깁니다. svn 속성 변경과 switched 상태는 복사로 재현할 수
            // 없고, 아래 switch가 다루지 않는 상태는 복사 대상도 아닙니다. 매핑에 남기면
            // 미리보기 숫자에도 안 세고 복사도 안 하면서 migratedPaths에만 들어갑니다.
            guard isReproducibleByCopy(entry.item),
                  entry.propertyState == .none,
                  !entry.isSwitched else {
                blockers.append(destination)
                return nil
            }

            if entry.item != .deleted && entry.item != .missing {
                let sourceURL = sourceRoot.appendingPathComponent(entry.path)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    blockers.append(destination)
                    return nil
                }
                if entry.item == .modified,
                   (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // 폴더 속성 변경은 파일 복사만으로 재현할 수 없습니다.
                    blockers.append(destination)
                    return nil
                }
            }

            return SVNRecoveryPathMapping(
                sourcePath: entry.path,
                destinationPath: destination,
                status: entry.item
            )
        }

        return SVNRecoveryPreview(
            mappings: mappings.sorted { $0.destinationPath < $1.destinationPath },
            ignoredAliasCount: snapshot.collisions.reduce(0) { $0 + $1.affectedEntryCount },
            blockingPaths: Array(Set(blockers)).sorted()
        )
    }

    static func requireEmptyDestination(_ destination: URL, fileManager: FileManager = .default) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw SVNError.recoveryDestinationNotEmpty }
            let contents = try fileManager.contentsOfDirectory(atPath: destination.path)
            guard contents.isEmpty else { throw SVNError.recoveryDestinationNotEmpty }
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }
    }

    static func apply(
        _ preview: SVNRecoveryPreview,
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        for mapping in preview.mappings {
            let targetURL = try safeURL(for: mapping.destinationPath, below: destination)
            switch mapping.status {
            case .deleted, .missing:
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
            case .modified, .replaced, .added, .unversioned:
                let sourceURL = try safeURL(for: mapping.sourcePath, below: source)
                try mergeCopy(from: sourceURL, to: targetURL, fileManager: fileManager)
            case .ignored, .conflicted, .unknown, .obstructed, .incomplete:
                // 방해 상태와 미완료 상태는 원본이 신뢰할 수 없으므로 복구에서 제외합니다.
                // `preview`가 이미 차단 목록으로 보내므로 여기에는 도달하지 않습니다.
                break
            }
        }
    }

    private static func mergeCopy(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } else if values.isDirectory == true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ) where child.lastPathComponent != ".svn" {
                let normalizedName = child.lastPathComponent.precomposedStringWithCanonicalMapping
                try mergeCopy(
                    from: child,
                    to: destination.appendingPathComponent(normalizedName),
                    fileManager: fileManager
                )
            }
        } else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private static func safeURL(for relativePath: String, below root: URL) throws -> URL {
        guard isSafeRelativePath(relativePath) else {
            throw SVNError.recoveryBlocked(paths: [relativePath])
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw SVNError.recoveryBlocked(paths: [relativePath])
        }
        return candidate
    }

    /// `apply`가 실제로 복사하거나 지우는 상태입니다. 이 목록과 `apply`의 switch는 함께 바뀝니다.
    private static func isReproducibleByCopy(_ status: SVNStatusKind) -> Bool {
        switch status {
        case .modified, .replaced, .added, .unversioned, .deleted, .missing:
            return true
        case .ignored, .conflicted, .obstructed, .incomplete, .unknown:
            return false
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, path != ".", !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}
