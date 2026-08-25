import Foundation
import Testing
import SVNCore
@testable import SVNMac

@Test func unlockedPathsRunOneExplicitMultiPathLockCommand() async throws {
    let client = RecordingMultiplePathLocker()
    let command = ExplicitLockCommand(
        paths: ["Documents/a.xlsx", "Documents/b.hwp"],
        force: false
    )

    try await ExplicitLockCommandRunner(client: client).run(
        command,
        workingCopyPath: "/tmp/project",
        comment: "editing",
        credentials: nil,
        allowUntrustedServerCertificate: false,
        allowedServerCertificateFailures: []
    )

    #expect(await client.commands == [command])
}

@Test func unlockedPathsDoNotRequireForceConfirmation() {
    let plan = ExplicitLockPlanner.plan(
        paths: ["Documents/b.hwp", "Documents/a.xlsx"],
        locks: [],
        username: "me"
    )

    #expect(plan == .run(ExplicitLockCommand(
        paths: ["Documents/a.xlsx", "Documents/b.hwp"],
        force: false
    )))
}

@Test func anotherOwnersLockRequiresConfirmationBeforeForceCommand() async throws {
    let lock = SVNLockInfo(path: "Documents/a.xlsx", owner: "other.user")
    let plan = ExplicitLockPlanner.plan(
        paths: ["Documents/a.xlsx"],
        locks: [lock],
        username: "me"
    )

    guard case let .confirmForce(request) = plan else {
        Issue.record("another owner's lock must require force confirmation")
        return
    }
    #expect(request.conflictingLocks == [lock])
    #expect(request.paths == ["Documents/a.xlsx"])

    let client = RecordingMultiplePathLocker()
    try await ExplicitLockCommandRunner(client: client).run(
        request.forceCommand,
        workingCopyPath: "/tmp/project",
        comment: "editing",
        credentials: nil,
        allowUntrustedServerCertificate: false,
        allowedServerCertificateFailures: []
    )
    #expect(await client.commands == [ExplicitLockCommand(paths: request.paths, force: true)])
}

@Test func bulkUnlockReportsExactPartialFailures() async {
    let locks = [
        SVNLockInfo(path: "Documents/a.xlsx", owner: "me"),
        SVNLockInfo(path: "Documents/b.hwp", owner: "me"),
        SVNLockInfo(path: "Documents/c.pdf", owner: "me"),
    ]

    let result = await BulkUnlockExecutor.run(locks) { lock in
        if lock.path == "Documents/b.hwp" { throw LockWorkflowTestError.denied }
    }

    #expect(result.releasedPaths == ["Documents/a.xlsx", "Documents/c.pdf"])
    #expect(result.failures.map(\.path) == ["Documents/b.hwp"])
    #expect(result.failures[0].message.contains("denied"))
}

@Test func bulkUnlockSelectsOnlyCurrentUsersLocks() {
    let locks = [
        SVNLockInfo(path: "Documents/a.xlsx", owner: "me"),
        SVNLockInfo(path: "Documents/b.hwp", owner: "other.user"),
    ]

    #expect(BulkUnlockPlanner.ownedLocks(in: locks, username: "me").map(\.path) == ["Documents/a.xlsx"])
    #expect(BulkUnlockPlanner.ownedLocks(in: locks, username: nil).isEmpty)
}

@Test func lockConfirmationsExplainOwnerImpactInBothLanguages() {
    let korean = AppLanguage.korean.localized(
        .ui.force.lockConfirmationDetails,
        1,
        "Documents/a.xlsx — other.user"
    )
    let english = AppLanguage.english.localized(
        .ui.bulk.unlockPartialFailureDetails,
        7,
        10,
        "Documents/b.hwp"
    )

    #expect(korean.contains("other.user"))
    #expect(korean.contains("기존 사용자가 잠금을 잃습니다"))
    #expect(english.contains("Released 7 of 10 locks"))
    #expect(english.contains("Documents/b.hwp"))
}

private actor RecordingMultiplePathLocker: MultiplePathLockServing {
    private(set) var commands: [ExplicitLockCommand] = []

    func lock(
        at _: String,
        relativePaths: [String],
        comment _: String,
        force: Bool,
        credentials _: SVNCredentials?,
        allowUntrustedServerCertificate _: Bool,
        allowedServerCertificateFailures _: Set<SVNServerCertificateFailure>
    ) async throws -> String {
        commands.append(ExplicitLockCommand(paths: relativePaths, force: force))
        return "locked"
    }
}

private enum LockWorkflowTestError: Error {
    case denied
}
