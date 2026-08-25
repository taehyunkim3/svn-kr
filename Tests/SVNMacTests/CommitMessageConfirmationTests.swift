import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Suite("CommitMessageConfirmationTests")
struct CommitMessageConfirmationTests {
    private let localizationKeys = [
        "ui.commit.without.a.message.6f0f2d41",
        "ui.the.commit.will.be.recorded.with.an.empty.messag.9c31be05",
        "ui.review.commit.8b36485e",
        "ui.server.deletion.count.793b7522",
        "ui.server.deletion.warning.81e94f35",
        "ui.restore.selected.server.files.4f2a7c91",
        "ui.restore.selected.files.confirmation.6d81b3e4",
        "ui.restore.selected.files.count.2c9f4a70",
        "ui.restore.selected.files.action.7b3e1d95",
        "ui.commit.deletion.restore.partial.5a8c2f64",
        "ui.restore.target.not.deleted.1d6a4b82",
        "ui.restored.selected.server.files.2e4c7a91",
        "ui.no.server.deletions.remaining.3e7b9a12",
        "ui.confirm.commit.7c2e5a90",
        "ui.no.bafd7322",
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

        #expect(commitControls.contains("store.prepareCommitConfirmation(message: message)"))
        #expect(commitControls.contains("store.commitConfirmationRequest"))
        #expect(confirmation.contains("ui.commit.without.a.message.6f0f2d41"))
        #expect(confirmation.contains("ui.the.commit.will.be.recorded.with.an.empty.messag.9c31be05"))
        for key in localizationKeys {
            #expect(
                commitControls.contains(key)
                    || confirmation.contains(key)
                    || fileActions.contains(key)
            )
        }
        #expect(confirmation.contains("store.confirmCommit(currentRequest)"))
    }

    @Test func confirmationShowsScrollableSelectableDeletionPathsAndBulkRestore() throws {
        let confirmation = try source(at: "Sources/SVNMac/CommitConfirmationView.swift")

        #expect(confirmation.contains("exclamationmark.triangle.fill"))
        #expect(confirmation.contains(".foregroundStyle(.orange)"))
        #expect(confirmation.contains("serverDeletionEntries.count"))
        #expect(confirmation.contains("List(serverDeletionEntries, selection: $store.selectedCommitDeletionRestorePaths)"))
        #expect(confirmation.contains("entry.path.precomposedStringWithCanonicalMapping"))
        #expect(confirmation.contains("store.requestCommitDeletionRestore()"))
        #expect(confirmation.contains("store.confirmCommitDeletionRestore(restoreRequest)"))
        #expect(confirmation.contains("restoreRequest.paths.count"))
        #expect(confirmation.contains("ui.no.server.deletions.remaining.3e7b9a12"))
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
            for key in localizationKeys {
                #expect(localization.contains(key))
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
