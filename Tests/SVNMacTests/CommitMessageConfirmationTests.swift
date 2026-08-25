import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Suite("CommitMessageConfirmationTests")
struct CommitMessageConfirmationTests {
    private let localizationKeys: [(key: LocalizationKey, sourceExpression: String)] = [
        (.ui.commit.withoutAMessage, ".ui.commit.withoutAMessage"),
        (.ui.the.commitWillBeRecordedWithAnEmptyMessag, ".ui.the.commitWillBeRecordedWithAnEmptyMessag"),
        (.ui.review.commit, ".ui.review.commit"),
        (.ui.server.deletionCount, ".ui.server.deletionCount"),
        (.ui.server.deletionWarning, ".ui.server.deletionWarning"),
        (.ui.restore.selectedServerFiles, ".ui.restore.selectedServerFiles"),
        (.ui.restore.selectedFilesConfirmation, ".ui.restore.selectedFilesConfirmation"),
        (.ui.restore.selectedFilesCount, ".ui.restore.selectedFilesCount"),
        (.ui.restore.selectedFilesAction, ".ui.restore.selectedFilesAction"),
        (.ui.commit.deletionRestorePartial, ".ui.commit.deletionRestorePartial"),
        (.ui.restore.targetNotDeleted, ".ui.restore.targetNotDeleted"),
        (.ui.restored.selectedServerFiles, ".ui.restored.selectedServerFiles"),
        (.ui.no.serverDeletionsRemaining, ".ui.no.serverDeletionsRemaining"),
        (.ui.confirm.commit, ".ui.confirm.commit"),
        (.ui.no.label, ".ui.no.label"),
    ]

    @Test func emptyMessageKeepsCommitButtonEnabled() throws {
        let commitControls = try source(at: "Sources/SVNMac/CommitControlsView.swift")
        let disabledStart = try #require(commitControls.range(of: ".disabled("))
        let sourceFromDisabled = commitControls[disabledStart.lowerBound...]
        let disabledEnd = try #require(sourceFromDisabled.range(of: "\n                )"))
        let disabledBlock = sourceFromDisabled[..<disabledEnd.upperBound]

        #expect(!disabledBlock.contains("commitMessage"))
        #expect(disabledBlock.contains("store.canCommitSelectedPaths"))
        #expect(disabledBlock.contains("store.isSelectedProjectActionBlocked"))
    }

    @Test func emptyMessageSubmissionUsesLocalizedConfirmation() throws {
        let commitControls = try source(at: "Sources/SVNMac/CommitControlsView.swift")
        let confirmation = try source(at: "Sources/SVNMac/CommitConfirmationView.swift")
        let fileActions = try source(at: "Sources/SVNMac/ProjectStore+FileActions.swift")
        let restoreConfirmation = try source(
            at: "Sources/SVNMac/CommitDeletionRestoreConfirmation.swift"
        )

        #expect(commitControls.contains("store.prepareCommitConfirmation(message: message)"))
        #expect(commitControls.contains("store.commitConfirmationRequest"))
        #expect(confirmation.contains(".ui.commit.withoutAMessage"))
        #expect(confirmation.contains(".ui.the.commitWillBeRecordedWithAnEmptyMessag"))
        for entry in localizationKeys {
            #expect(
                commitControls.contains(entry.sourceExpression)
                    || confirmation.contains(entry.sourceExpression)
                    || fileActions.contains(entry.sourceExpression)
                    || restoreConfirmation.contains(entry.sourceExpression)
            )
        }
        #expect(confirmation.contains("store.confirmCommit(currentRequest)"))
    }

    @Test func confirmationShowsScrollableSelectableDeletionPathsAndBulkRestore() throws {
        let confirmation = try source(at: "Sources/SVNMac/CommitConfirmationView.swift")
        let restoreConfirmation = try source(
            at: "Sources/SVNMac/CommitDeletionRestoreConfirmation.swift"
        )

        #expect(confirmation.contains("exclamationmark.triangle.fill"))
        #expect(confirmation.contains(".foregroundStyle(.orange)"))
        #expect(confirmation.contains("serverDeletionEntries.count"))
        #expect(confirmation.contains("ForEach(serverDeletionEntries)"))
        #expect(confirmation.contains("store.selectedCommitDeletionRestorePaths.insert(entry.path)"))
        #expect(confirmation.contains("store.selectedCommitDeletionRestorePaths.remove(entry.path)"))
        #expect(confirmation.contains(".labelsHidden()"))
        #expect(confirmation.contains("entry.path.precomposedStringWithCanonicalMapping"))
        #expect(confirmation.contains("store.requestCommitDeletionRestore()"))
        #expect(confirmation.contains(".commitDeletionRestoreConfirmation()"))
        #expect(restoreConfirmation.contains("store.confirmCommitDeletionRestore(restoreRequest)"))
        #expect(restoreConfirmation.contains("restoreRequest.paths.count"))
        #expect(confirmation.contains(".ui.no.serverDeletionsRemaining"))
        #expect(confirmation.contains("AppLayout.commitConfirmationSheetMinimumSize"))
        #expect(!confirmation.contains("DisclosureGroup"))
    }

    @Test func serverDeletionListExcludesMissingScheduledAddition() {
        let deleted = SVNStatusEntry(path: "scheduled.txt", item: .deleted, revision: "10")
        let missing = SVNStatusEntry(path: "finder.txt", item: .missing, revision: "10")
        let missingAddition = SVNStatusEntry(path: "never-added.txt", item: .missing, revision: "-1")
        let modified = SVNStatusEntry(path: "edited.txt", item: .modified, revision: "10")
        let request = CommitConfirmationRequest(
            projectID: UUID(),
            message: "삭제",
            selectedPaths: Set([deleted, missing, missingAddition, modified].map(\.path)),
            statuses: [deleted, missing, missingAddition, modified]
        )

        #expect(request.serverDeletionEntries == [missing, deleted])
    }

    @Test func emptyMessageConfirmationIsLocalizedInEveryResource() throws {
        let localizationPaths = [
            "Sources/SVNMac/Resources/Localizable.xcstrings",
            "Sources/SVNMac/Resources/ko.lproj/Localizable.strings",
            "Sources/SVNMac/Resources/en.lproj/Localizable.strings",
        ]

        for path in localizationPaths {
            let localization = try source(at: path)
            for entry in localizationKeys {
                #expect(localization.contains(entry.key.rawValue))
            }
        }
    }

    @Test func koreanDeletionWarningMatchesProductCopy() throws {
        let korean = try source(at: "Sources/SVNMac/Resources/ko.lproj/Localizable.strings")

        #expect(korean.contains(
            "삭제하는 파일이 있습니다. 정말 삭제하는게 맞는지 아래 목록에서 확인해주세요."
        ))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
