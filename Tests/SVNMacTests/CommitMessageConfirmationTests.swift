import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Suite("CommitMessageConfirmationTests")
struct CommitMessageConfirmationTests {
    private let localizationKeys: [(key: LocalizationKey, sourceExpression: String)] = [
        (.ui.commit.withoutMessage, ".ui.commit.withoutMessage"),
        (.ui.commit.recordedEmptyMessage, ".ui.commit.recordedEmptyMessage"),
        (.ui.commit.reviewCommit, ".ui.commit.reviewCommit"),
        (.ui.commit.itemDeletedServer, ".ui.commit.itemDeletedServer"),
        (.ui.commit.someFilesDeletedReviewListBelowConfirmThatTheyShould, ".ui.commit.someFilesDeletedReviewListBelowConfirmThatTheyShould"),
        (.ui.commit.restoreSelectedFilesAction, ".ui.commit.restoreSelectedFilesAction"),
        (.ui.commit.restoreSelectedFilesConfirmationTitle, ".ui.commit.restoreSelectedFilesConfirmationTitle"),
        (.ui.commit.restoreSelectedDeletionFileServer, ".ui.commit.restoreSelectedDeletionFileServer"),
        (.ui.commit.restoreServer, ".ui.commit.restoreServer"),
        (.ui.file.restoredButFailed, ".ui.file.restoredButFailed"),
        (.ui.file.noLongerMarkedDeleted, ".ui.file.noLongerMarkedDeleted"),
        (.ui.file.restoredSelectedDeletionFileServer, ".ui.file.restoredSelectedDeletionFileServer"),
        (.ui.commit.noFilesDeleted, ".ui.commit.noFilesDeleted"),
        (.ui.commit.confirm, ".ui.commit.confirm"),
        (.ui.commit.no, ".ui.commit.no"),
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
        #expect(confirmation.contains(".ui.commit.withoutMessage"))
        #expect(confirmation.contains(".ui.commit.recordedEmptyMessage"))
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
        #expect(confirmation.contains(".ui.commit.noFilesDeleted"))
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
