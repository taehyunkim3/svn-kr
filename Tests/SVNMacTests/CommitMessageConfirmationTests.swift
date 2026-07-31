import Foundation
import Testing

@Suite("CommitMessageConfirmationTests")
struct CommitMessageConfirmationTests {
    private let localizationKeys = [
        "ui.commit.without.a.message.6f0f2d41",
        "ui.the.commit.will.be.recorded.with.an.empty.messag.9c31be05",
        "ui.yes.93cba074",
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

        #expect(commitControls.contains("isConfirmingEmptyMessageCommit"))
        for key in localizationKeys {
            #expect(commitControls.contains(key))
        }
        #expect(commitControls.contains("store.commit(message: \"\")"))
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
