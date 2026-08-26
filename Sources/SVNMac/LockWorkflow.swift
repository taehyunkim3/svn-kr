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
        let requestedPaths = Array(Set(paths)).sorted()
        let ownedPaths = Set(BulkUnlockPlanner.ownedLocks(in: locks, username: username).map(\.path))
        let pathsToLock = requestedPaths.filter { !containsPath(ownedPaths, path: $0) }
        guard !pathsToLock.isEmpty else { return .noAction }

        let conflictingLocks = locks.filter { lock in
            pathsToLock.contains { pathsMatch($0, lock.path) }
        }
        guard conflictingLocks.isEmpty else {
            return .confirmForce(ExplicitLockRequest(
                paths: pathsToLock,
                conflictingLocks: conflictingLocks.sorted { $0.path < $1.path }
            ))
        }
        return .run(ExplicitLockCommand(paths: pathsToLock, force: false))
    }

    private static func containsPath(_ paths: Set<String>, path: String) -> Bool {
        paths.contains { pathsMatch($0, path) }
    }

    private static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        Data(lhs.utf8) == Data(rhs.utf8)
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
