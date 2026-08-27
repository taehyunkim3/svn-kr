import Foundation
import Testing
import SVNCore
@testable import SVNMac

@Test func forceUnlockFailuresExplainKnownCodesAndPreserveUnknownCodes() {
    let baseMessage = "잠금 강제 해제 실패"

    #expect(SVNErrorLocalization.forceUnlockFailureMessage(
        for: SVNError.commandFailed(
            command: "svn unlock --force",
            message: "svn: E165001: Lock owner mismatch"
        ),
        localizedMessage: baseMessage,
        language: .korean
    ) == "잠금 강제 해제 실패\n\nE165001: 서버의 pre-unlock 훅이 잠금 소유자만 해제하도록 제한했습니다.")
    #expect(SVNErrorLocalization.forceUnlockFailureMessage(
        for: SVNError.commandFailed(
            command: "svn unlock --force",
            message: "svn: E170001: Authentication required"
        ),
        localizedMessage: baseMessage,
        language: .korean
    ) == "잠금 강제 해제 실패\n\nE170001: 인증이 필요하거나 실패했습니다.")
    #expect(SVNErrorLocalization.forceUnlockFailureMessage(
        for: SVNError.commandFailed(
            command: "svn unlock --force",
            message: "svn: E215004: No more credentials"
        ),
        localizedMessage: baseMessage,
        language: .korean
    ) == "잠금 강제 해제 실패\n\nE215004: 인증이 필요하거나 실패했습니다.")
    #expect(SVNErrorLocalization.forceUnlockFailureMessage(
        for: SVNError.commandFailed(
            command: "svn unlock --force",
            message: "svn: E175013: Access forbidden"
        ),
        localizedMessage: baseMessage,
        language: .korean
    ) == "잠금 강제 해제 실패\n\nE175013: 서버가 접근을 거부했습니다(HTTP 403).")
    #expect(SVNErrorLocalization.forceUnlockFailureMessage(
        for: SVNError.commandFailed(
            command: "svn unlock --force",
            message: "svn: E200009: Could not unlock"
        ),
        localizedMessage: baseMessage,
        language: .korean
    ) == "잠금 강제 해제 실패\n\nSVN 오류 코드: E200009")
}

@Test func forceUnlockFailureWithoutCodeKeepsExistingLocalizedMessage() {
    let baseMessage = "잠금 강제 해제 실패"

    #expect(SVNErrorLocalization.forceUnlockFailureMessage(
        for: SVNError.commandFailed(
            command: "svn unlock --force",
            message: "Could not unlock"
        ),
        localizedMessage: baseMessage,
        language: .korean
    ) == baseMessage)
}

@Test func fileLockActionAvailabilityDistinguishesNeedsLockStates() {
    let path = "Documents/report.hwp"

    #expect(FileLockActionAvailability.resolve(
        path: path,
        needsLockPaths: [path],
        loadedNeedsLockPaths: [path]
    ) == .enabled)
    #expect(FileLockActionAvailability.resolve(
        path: path,
        needsLockPaths: [],
        loadedNeedsLockPaths: [path]
    ) == .needsLockMissing)
    #expect(FileLockActionAvailability.resolve(
        path: path,
        needsLockPaths: [],
        loadedNeedsLockPaths: []
    ) == .checkingNeedsLock)
    #expect(FileLockActionAvailability.needsLockMissing.helpMessage(
        language: .korean,
        fallback: ""
    ) == "이 파일에는 svn:needs-lock 속성이 없어 잠금 기능을 사용할 수 없습니다. 먼저 ‘편집 전 잠금 강제’를 설정하고 커밋하세요.")
    #expect(FileLockActionAvailability.checkingNeedsLock.helpMessage(
        language: .english,
        fallback: ""
    ) == "Checking the svn:needs-lock property.")
}

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

@Test func canonicalAliasLockRequiresConfirmationBeforeForceCommand() {
    let repositoryPath = "문서/주간보고서.hwp"
    let localPath = repositoryPath.decomposedStringWithCanonicalMapping
    let lock = SVNLockInfo(path: repositoryPath, owner: "other.user")

    let plan = ExplicitLockPlanner.plan(
        paths: [localPath],
        locks: [lock],
        username: "me"
    )

    guard case let .confirmForce(request) = plan else {
        Issue.record("canonical alias lock must require force confirmation")
        return
    }
    #expect(request.conflictingLocks == [lock])
    #expect(request.paths.count == 1)
    #expect(Data(request.paths[0].utf8) == Data(localPath.utf8))
}

@Test func canonicalCollisionKeepsDistinctLockPathsByteExact() {
    let composed = "문서/주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    let locks = [
        SVNLockInfo(path: composed, owner: "other.user"),
        SVNLockInfo(path: decomposed, owner: "me"),
    ]

    let plan = ExplicitLockPlanner.plan(
        paths: [decomposed],
        locks: locks,
        username: "me"
    )

    #expect(plan == .noAction)
}

@Test func canonicalCollisionDoesNotTreatOtherRawPathAsOwned() {
    let composed = "문서/주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    let otherLock = SVNLockInfo(path: composed, owner: "other.user")
    let locks = [
        otherLock,
        SVNLockInfo(path: decomposed, owner: "me"),
    ]

    let plan = ExplicitLockPlanner.plan(
        paths: [composed],
        locks: locks,
        username: "me"
    )

    guard case let .confirmForce(request) = plan else {
        Issue.record("raw-distinct other lock must require force confirmation")
        return
    }
    #expect(request.conflictingLocks == [otherLock])
}

@Test func canonicalCollisionPreservesBothRequestedRawPaths() {
    let composed = "문서/주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping

    let plan = ExplicitLockPlanner.plan(
        paths: [composed, decomposed],
        locks: [],
        username: "me"
    )

    guard case let .run(command) = plan else {
        Issue.record("raw-distinct paths must remain separate lock targets")
        return
    }
    #expect(command.paths.count == 2)
    #expect(Set(command.paths.map { SVNPathIdentity(rawPath: $0) }).count == 2)
}

@Test func changesLockMatchingUsesCanonicalAliasOnlyWhenUnambiguous() {
    let composed = "문서/주간보고서.hwp"
    let decomposed = composed.decomposedStringWithCanonicalMapping
    let composedLock = SVNLockInfo(path: composed, owner: "other.user")

    #expect(ChangesLockMatcher.lockInfo(
        for: decomposed,
        in: [composedLock]
    ) == composedLock)
    #expect(ChangesLockMatcher.lockInfo(
        for: composed,
        in: [
            composedLock,
            SVNLockInfo(path: decomposed, owner: "me"),
        ]
    ) == composedLock)

    let fullyDecomposed = "각.hwp".decomposedStringWithCanonicalMapping
    let partiallyDecomposed = "가\u{11A8}.hwp"
    #expect(ChangesLockMatcher.lockInfo(
        for: partiallyDecomposed,
        in: [
            SVNLockInfo(path: "각.hwp", owner: "other.user"),
            SVNLockInfo(path: fullyDecomposed, owner: "me"),
        ]
    ) == nil)
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
        .ui.lock.forceLockingSelectedFileRemovesExistingUsersLocksReviewOwners,
        1,
        "Documents/a.xlsx — other.user"
    )
    let english = AppLanguage.english.localized(
        .ui.lock.releasedLocksLocksBelowCouldNotReleased,
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
