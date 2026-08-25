import Foundation
import Testing
@testable import SVNMac

@Suite("DestructiveReturnKeyTests")
struct DestructiveReturnKeyTests {
    @Test func commitConfirmationBindsReturnToConfirmOnlyWhenNoServerDeletions() throws {
        let source = try source(named: "CommitConfirmationView.swift")
        let confirmButton = try modifierBlock(
            in: source,
            after: ".ui.confirm.commit",
            endingWith: ".disabled(store.isSelectedProjectActionBlocked)"
        )

        #expect(confirmButton.contains("serverDeletionEntries.isEmpty"))
        let returnIsGated = !confirmButton.contains(".keyboardShortcut(.defaultAction)")
            || confirmButton.contains("isEmpty")
        #expect(returnIsGated)
    }

    @Test func commitConfirmationKeepsEscapeOnCancel() throws {
        let source = try source(named: "CommitConfirmationView.swift")
        let keepsEscape = source.contains("role: .cancel")
            && source.contains(".cancelAction")

        #expect(keepsEscape)
    }

    @Test func pathNormalizationConfirmationDoesNotBindReturnToCommit() throws {
        let source = try source(named: "RepositoryPathNormalizationView.swift")
        let confirmationStart = try #require(
            source.range(of: "private struct RepositoryPathNormalizationConfirmationView")
        )
        let confirmation = String(source[confirmationStart.lowerBound...])
        let runButton = try modifierBlock(
            in: confirmation,
            after: ".repository.pathNormalizationConfirmationRun",
            endingWith: ".disabled(!store.canConfirmRepositoryPathNormalization)"
        )

        #expect(!runButton.contains(".keyboardShortcut(.defaultAction)"))
        #expect(confirmation.contains("role: .cancel"))
        let keepsKeyboardCancel = confirmation.contains(".keyboardShortcut(.cancelAction)")
            || confirmation.contains(".keyboardShortcut(.defaultAction)")
        #expect(keepsKeyboardCancel)
    }

    @Test func deletionConfirmationDoesNotBindReturnToMarkForDeletion() throws {
        let source = try source(named: "DeletionConfirmationView.swift")
        let destructiveButton = try modifierBlock(
            in: source,
            after: "Button(role: .destructive)",
            endingWith: ".disabled(store.isSelectedProjectActionBlocked)"
        )

        #expect(!destructiveButton.contains(".keyboardShortcut(.defaultAction)"))
        #expect(source.contains("role: .cancel"))
        let keepsKeyboardCancel = source.contains(".keyboardShortcut(.cancelAction)")
            || source.contains(".keyboardShortcut(.defaultAction)")
        #expect(keepsKeyboardCancel)
    }

    @Test func revertConfirmationUsesDestructiveRoleWithoutReturnBinding() throws {
        let source = try source(named: "RevertConfirmation.swift")

        #expect(source.contains("role: .destructive"))
        #expect(source.contains("role: .cancel"))
        #expect(!source.contains(".keyboardShortcut(.defaultAction)"))
    }

    @Test func commitDeletionRestoreIsRecoveryNotDestructiveDefault() throws {
        let source = try source(named: "CommitDeletionRestoreConfirmation.swift")

        #expect(!source.contains("role: .destructive"))
        #expect(source.contains("role: .cancel"))
        #expect(!source.contains(".keyboardShortcut(.defaultAction)"))
    }

    private func modifierBlock(
        in source: String,
        after marker: String,
        endingWith suffix: String
    ) throws -> String {
        let start = try #require(source.range(of: marker))
        let fromMarker = source[start.lowerBound...]
        let end = try #require(fromMarker.range(of: suffix))
        return String(fromMarker[..<end.upperBound])
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
