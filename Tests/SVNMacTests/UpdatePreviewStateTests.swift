import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func updatePreviewKeepsCommitDetails() {
    let date = Date(timeIntervalSince1970: 1_768_173_600)
    let changedPaths = [
        SVNChangedPath(path: "/trunk/추가.xlsx", action: .added, kind: .file),
        SVNChangedPath(path: "/trunk/수정.xlsx", action: .modified, kind: .file),
        SVNChangedPath(path: "/trunk/삭제.xlsx", action: .deleted, kind: .file),
        SVNChangedPath(path: "/trunk/교체.xlsx", action: .replaced, kind: .file),
    ]
    let commit = SVNLogEntry(
        revision: "1845",
        author: "kim.office",
        date: date,
        message: "분기 보고서 수정",
        changedPaths: changedPaths
    )
    var state = UpdatePreviewState()

    state.receive([commit])

    #expect(state.commits.count == 1)
    #expect(state.commits[0].revision == "1845")
    #expect(state.commits[0].author == "kim.office")
    #expect(state.commits[0].date == date)
    #expect(state.commits[0].message == "분기 보고서 수정")
    #expect(state.commits[0].changedPaths == changedPaths)
}

@Test func updatePreviewCommitsStartCollapsedAndCanToggle() {
    var state = UpdatePreviewState()
    state.receive([makeUpdatePreviewCommit(revision: "42")])

    #expect(!state.isExpanded("42"))

    state.setExpanded(true, revision: "42")
    #expect(state.isExpanded("42"))

    state.setExpanded(false, revision: "42")
    #expect(!state.isExpanded("42"))
}

@Test func updatePreviewFailureStillAllowsUpdateAttempt() {
    var state = UpdatePreviewState()
    state.recordFailure("서버에 연결할 수 없습니다.")

    #expect(state.errorMessage == "서버에 연결할 수 없습니다.")
    #expect(state.canRunUpdate(hasRemoteChanges: false, isWorkingCopyOutOfDate: false))
}

@Test func updatePreviewReportsCommitLimit() {
    let commits = (1 ... UpdatePreviewState.maximumVisibleCommitCount + 1).map {
        makeUpdatePreviewCommit(revision: String($0))
    }
    var state = UpdatePreviewState()

    state.receive(commits)

    #expect(state.commits.count == UpdatePreviewState.maximumVisibleCommitCount)
    #expect(state.totalCommitCount == UpdatePreviewState.maximumVisibleCommitCount + 1)
    #expect(state.isTruncated)
}

@Test func updatePreviewViewKeepsUpdateAndCleanupActions() throws {
    let sources = try svnMacSourcesForUpdatePreviewTests()
    let view = try String(
        contentsOf: sources.appendingPathComponent("UpdatePreviewView.swift"),
        encoding: .utf8
    )
    let update = try String(
        contentsOf: sources.appendingPathComponent("ProjectStore+Update.swift"),
        encoding: .utf8
    )

    #expect(view.contains("Task { await store.update() }"))
    #expect(view.contains("$store.cleansRepositoryTemporaryFilesAfterUpdate"))
    #expect(update.contains("let preparesCleanup = cleansRepositoryTemporaryFilesAfterUpdate"))
    #expect(update.contains("try await client.update("))
}

@Test func updatePreviewUsesSharedHistoryPresentationAndLocalizedNotices() throws {
    let sources = try svnMacSourcesForUpdatePreviewTests()
    let view = try String(
        contentsOf: sources.appendingPathComponent("UpdatePreviewView.swift"),
        encoding: .utf8
    )

    #expect(view.contains("HistoryDateFormatting.shared.string("))
    #expect(view.contains("SVNLogMessageView(entry: entry)"))
    #expect(view.contains("ContentUnavailableView("))
    #expect(view.contains("ui.preview.failed.update.still.available.2c71be90"))
    #expect(view.contains("preview.canRunUpdate("))
    #expect(view.contains("UpdatePreviewState.maximumVisibleCommitCount"))
    #expect(
        AppLanguage.korean.localized("ui.showing.first.commits.of.total.8d6f4a21", 100, 101)
            == "전체 101개 커밋 중 처음 100개만 표시합니다."
    )
    #expect(
        AppLanguage.english.localized("ui.showing.first.commits.of.total.8d6f4a21", 100, 101)
            == "Showing the first 100 of 101 commits."
    )
    #expect(
        AppLanguage.korean.localized(
            "ui.preview.failed.update.still.available.2c71be90",
            "네트워크 오류"
        ) == "업데이트 미리보기 전체를 불러오지 못했습니다. 그래도 업데이트를 시도할 수 있습니다.\n\n네트워크 오류"
    )
}

@Test func updatePreviewStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.showing.first.commits.of.total.8d6f4a21",
        "ui.preview.failed.update.still.available.2c71be90",
    ]
    let resources = try svnMacSourcesForUpdatePreviewTests()
        .appendingPathComponent("Resources", isDirectory: true)
    let localizationFiles = [
        resources.appendingPathComponent("Localizable.xcstrings"),
        resources.appendingPathComponent("ko.lproj/Localizable.strings"),
        resources.appendingPathComponent("en.lproj/Localizable.strings"),
    ]

    for file in localizationFiles {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for key in keys {
            #expect(contents.contains(key), "\(key) is missing from \(file.path)")
        }
    }
}

private func makeUpdatePreviewCommit(revision: String) -> SVNLogEntry {
    SVNLogEntry(
        revision: revision,
        author: "author",
        date: Date(timeIntervalSince1970: 1_768_173_600),
        message: "message",
        changedPaths: [SVNChangedPath(path: "/trunk/file.txt", action: .modified)]
    )
}

private func svnMacSourcesForUpdatePreviewTests() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
