import Foundation
import SVNCore

struct ExplicitLockCommand: Equatable, Sendable {
    let paths: [String]
    let force: Bool
}

struct ExplicitLockRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let paths: [String]
    let conflictingLocks: [SVNLockInfo]

    var forceCommand: ExplicitLockCommand {
        ExplicitLockCommand(paths: paths, force: true)
    }
}

enum ExplicitLockPlan: Equatable, Sendable {
    case noAction
    case run(ExplicitLockCommand)
    case confirmForce(ExplicitLockRequest)
}

enum ExplicitLockPlanner {
    static func plan(
        paths: [String],
        locks: [SVNLockInfo],
        username: String?
    ) -> ExplicitLockPlan {
        var seenRequestedPaths: Set<SVNPathIdentity> = []
        let requestedPaths = paths
            .filter { seenRequestedPaths.insert(SVNPathIdentity(rawPath: $0)).inserted }
            .sorted { Data($0.utf8).lexicographicallyPrecedes(Data($1.utf8)) }
        let lockPaths = locks.map(\.path)
        let ownedPaths = BulkUnlockPlanner.ownedLocks(in: locks, username: username).map(\.path)
        let pathsToLock = requestedPaths.filter {
            !containsPath(ownedPaths, path: $0, among: lockPaths)
        }
        guard !pathsToLock.isEmpty else { return .noAction }

        let conflictingLocks = locks.filter { lock in
            pathsToLock.contains {
                CanonicalPathMatcher.matches($0, candidate: lock.path, among: lockPaths)
            }
        }
        guard conflictingLocks.isEmpty else {
            return .confirmForce(ExplicitLockRequest(
                paths: pathsToLock,
                conflictingLocks: conflictingLocks.sorted { $0.path < $1.path }
            ))
        }
        return .run(ExplicitLockCommand(paths: pathsToLock, force: false))
    }

    private static func containsPath(
        _ paths: [String],
        path: String,
        among candidates: [String]
    ) -> Bool {
        paths.contains {
            CanonicalPathMatcher.matches(path, candidate: $0, among: candidates)
        }
    }
}

enum CanonicalPathMatcher {
    /// 파일시스템과 SVN이 같은 경로를 NFC/NFD로 다르게 줄 때만 정규 키로 연결합니다.
    /// 같은 정규 키의 원문 경로가 둘 이상이면 실제로 다른 SVN 노드일 수 있으므로
    /// 원문 UTF-8 바이트가 같은 후보만 연결합니다.
    static func matches(_ path: String, candidate: String, among candidates: [String]) -> Bool {
        let pathIdentity = SVNPathIdentity(rawPath: path)
        let candidateIdentity = SVNPathIdentity(rawPath: candidate)
        if pathIdentity == candidateIdentity { return true }
        guard pathIdentity.canonicalKey == candidateIdentity.canonicalKey else { return false }
        let canonicalCandidates = Set(candidates.lazy.compactMap { value -> SVNPathIdentity? in
            let identity = SVNPathIdentity(rawPath: value)
            return identity.canonicalKey == pathIdentity.canonicalKey ? identity : nil
        })
        return canonicalCandidates.count == 1
    }
}

protocol MultiplePathLockServing: Sendable {
    func lock(
        at path: String,
        relativePaths: [String],
        comment: String,
        force: Bool,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    ) async throws -> String
}

extension SVNClient: MultiplePathLockServing {}

enum ExplicitLockExecutionError: LocalizedError {
    case forceUnsupported

    var errorDescription: String? {
        switch self {
        case .forceUnsupported:
            AppLanguage.current.localized(.ui.lock.currentSvnClientDoesNotSupportForcedMultiFileLocking)
        }
    }
}

struct ExplicitLockCommandRunner {
    let client: any MultiplePathLockServing

    func run(
        _ command: ExplicitLockCommand,
        workingCopyPath: String,
        comment: String,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    ) async throws {
        _ = try await client.lock(
            at: workingCopyPath,
            relativePaths: command.paths,
            comment: comment,
            force: command.force,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
    }
}

struct BulkUnlockRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let locks: [SVNLockInfo]
}

struct BulkUnlockFailure: Equatable, Sendable {
    let path: String
    let message: String
}

struct BulkUnlockResult: Equatable, Sendable {
    let requestedCount: Int
    let releasedPaths: [String]
    let failures: [BulkUnlockFailure]
}

enum BulkUnlockPlanner {
    static func ownedLocks(in locks: [SVNLockInfo], username: String?) -> [SVNLockInfo] {
        guard let username, !username.isEmpty else { return [] }
        return locks.filter { $0.owner == username }.sorted { $0.path < $1.path }
    }
}

enum BulkUnlockExecutor {
    static func run(
        _ locks: [SVNLockInfo],
        unlock: @Sendable (SVNLockInfo) async throws -> Void
    ) async -> BulkUnlockResult {
        var releasedPaths: [String] = []
        var failures: [BulkUnlockFailure] = []
        for lock in locks {
            do {
                try await unlock(lock)
                releasedPaths.append(lock.path)
            } catch {
                failures.append(BulkUnlockFailure(
                    path: lock.path,
                    message: String(describing: error)
                ))
            }
        }
        return BulkUnlockResult(
            requestedCount: locks.count,
            releasedPaths: releasedPaths,
            failures: failures
        )
    }
}
