import Foundation
import Testing
@testable import SVNMac

@Suite("DestructiveReturnKeyTests")
struct DestructiveReturnKeyTests {
    @Test(
        "Commit confirmation keyboard behavior",
        arguments: [CommitServerDeletionState.none, .present],
        [CommitMessageState.empty, .present]
    )
    func commitConfirmationKeyboardBehavior(
        serverDeletions: CommitServerDeletionState,
        message: CommitMessageState
    ) {
        let behavior = ConfirmationKeyboardBehavior.commitConfirmation(
            serverDeletions: serverDeletions,
            message: message
        )

        #expect(
            behavior.returnAction
                == (serverDeletions == .none ? .confirmCommit : nil),
            "서버 삭제가 있으면 Return이 어떤 동작도 실행하면 안 된다."
        )
        #expect(behavior.escapeAction == .cancel)
    }

    @Test func pathNormalizationConfirmationKeyboardBehavior() {
        let behavior = ConfirmationKeyboardBehavior.repositoryPathNormalization

        #expect(behavior.returnAction == .cancel)
        #expect(behavior.escapeAction == .cancel)
    }

    @Test func deletionConfirmationKeyboardBehavior() {
        let behavior = ConfirmationKeyboardBehavior.deletion

        #expect(behavior.returnAction == .cancel)
        #expect(behavior.escapeAction == .cancel)
    }

    @Test func revertConfirmationKeyboardBehavior() {
        let behavior = ConfirmationKeyboardBehavior.revert

        #expect(behavior.returnAction == nil)
        #expect(behavior.escapeAction == .cancel)
    }

    @Test func commitDeletionRestoreKeyboardBehavior() {
        let behavior = ConfirmationKeyboardBehavior.commitDeletionRestore

        #expect(behavior.returnAction == nil)
        #expect(behavior.escapeAction == .cancel)
    }

    @Test(
        "Document open confirmation keyboard behavior",
        arguments: [DocumentLockState.unlocked, .locked, .unavailable],
        [RememberOpenWithoutLockState.disabled, .enabled]
    )
    func documentOpenConfirmationKeyboardBehavior(
        lock: DocumentLockState,
        rememberOpenWithoutLock: RememberOpenWithoutLockState
    ) {
        let behavior = ConfirmationKeyboardBehavior.documentOpenConfirmation(
            lock: lock,
            rememberOpenWithoutLock: rememberOpenWithoutLock
        )

        #expect(
            behavior.returnAction == .openWithoutLock,
            "문서 열기 확인의 Return은 잠금 없이 열기를 실행해야 한다."
        )
        #expect(behavior.escapeAction == .cancel)
    }

    @Test func destructiveAndRecoveryButtonRolesRemainExplicit() throws {
        let commit = try source(named: "CommitConfirmationView.swift")
        let normalization = try source(named: "RepositoryPathNormalizationView.swift")
        let deletion = try source(named: "DeletionConfirmationView.swift")
        let revert = try source(named: "RevertConfirmation.swift")
        let restore = try source(named: "CommitDeletionRestoreConfirmation.swift")
        let normalizationConfirmationStart = try #require(
            normalization.range(
                of: "private struct RepositoryPathNormalizationConfirmationView"
            )
        )
        let normalizationConfirmation = normalization[normalizationConfirmationStart.lowerBound...]

        #expect(commit.contains("Button(appLanguage.localized(.ui.commit.no), role: .cancel)"))
        #expect(normalizationConfirmation.contains("role: .cancel"))
        #expect(deletion.contains("Button(role: .destructive)"))
        #expect(deletion.contains("role: .cancel"))
        #expect(revert.contains("role: .destructive"))
        #expect(revert.contains("role: .cancel"))
        #expect(!restore.contains("role: .destructive"))
        #expect(restore.contains("role: .cancel"))
    }

    private func source(named name: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/SVNMac/\(name)"),
            encoding: .utf8
        )
    }
}
