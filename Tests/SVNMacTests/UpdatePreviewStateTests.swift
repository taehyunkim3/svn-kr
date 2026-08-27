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

@Test func updatePreviewCommitsStartExpandedAndCanToggle() {
    var state = UpdatePreviewState()
    state.receive([makeUpdatePreviewCommit(revision: "42")])

    #expect(state.isExpanded("42"))

    state.setExpanded(false, revision: "42")
    #expect(!state.isExpanded("42"))

    state.setExpanded(true, revision: "42")
    #expect(state.isExpanded("42"))
}

@Test func updatePreviewFailureStillAllowsUpdateAttempt() {
    var state = UpdatePreviewState()
    state.recordFailure("서버에 연결할 수 없습니다.")

    #expect(state.errorMessage == "서버에 연결할 수 없습니다.")
    #expect(state.canRunUpdate(hasRemoteChanges: false, isWorkingCopyOutOfDate: false))
}

@MainActor
@Test func updatePreviewCleanupFailureOffersWorkingCopyRecovery() async {
    let project = SVNProject(
        name: "프로젝트",
        path: "/tmp/update-preview-cleanup",
        username: "office.user"
    )
    let error = SVNError.commandFailed(
        command: "svn status --show-updates",
        message: "svn: E155004: Working copy locked"
    )
    let store = makeUpdatePreviewFailureStore(project: project, error: error)

    await store.previewUpdate()

    #expect(store.workingCopyCleanupRequest?.projectID == project.id)
    #expect(store.workingCopyCleanupRequest?.originalMessage.contains("E155004") == true)
    #expect(!store.automaticRefreshCanRun(for: project))
    #expect(!store.isShowingUpdatePreview)
    #expect(store.errorMessage == nil)
    #expect(store.recoveryState.updatePreview.errorMessage?.contains("E155004") == true)
}

@MainActor
@Test func updatePreviewKeychainFailureOpensAuthentication() async {
    let project = SVNProject(
        name: "프로젝트",
        path: "/tmp/update-preview-authentication",
        username: "office.user"
    )
    let store = makeUpdatePreviewFailureStore(
        project: project,
        error: KeychainStoreError.accessDenied,
        mode: .incomingAndRemote
    )

    await store.previewUpdate()

    #expect(store.authenticationRequest?.projectID == project.id)
    #expect(store.authenticationRequest?.action == .update)
    #expect(!store.isShowingUpdatePreview)
    #expect(store.recoveryState.updatePreview.errorMessage != nil)
}

@MainActor
@Test func updatePreviewRemoteFailureUsesInlineErrorWithoutDuplicatePresenter() async {
    let project = SVNProject(
        name: "프로젝트",
        path: "/tmp/update-preview-network",
        username: "office.user"
    )
    let error = SVNError.commandFailed(
        command: "svn status --show-updates",
        message: "svn: E170013: Unable to connect to a repository"
    )
    let store = makeUpdatePreviewFailureStore(project: project, error: error)

    await store.previewUpdate()

    #expect(store.isShowingUpdatePreview)
    #expect(store.recoveryState.updatePreview.errorMessage?.contains("E170013") == true)
    #expect(store.errorMessage == nil)
    #expect(store.workingCopyCleanupRequest == nil)
    #expect(store.authenticationRequest == nil)
    #expect(!store.automaticRefreshCanRun(for: project))
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
    #expect(
        update.components(separatedBy: "recordUpdatePreviewFailure(error, project: project)").count - 1
            == 2
    )
}

@Test func updatePreviewUsesTheInjectedSVNClientWithoutRuntimeCasting() throws {
    let sources = try svnMacSourcesForUpdatePreviewTests()
    let dependencies = try String(
        contentsOf: sources.appendingPathComponent("ProjectDependencies.swift"),
        encoding: .utf8
    )
    let update = try String(
        contentsOf: sources.appendingPathComponent("ProjectStore+Update.swift"),
        encoding: .utf8
    )
    let state = try String(
        contentsOf: sources.appendingPathComponent("UpdatePreviewState.swift"),
        encoding: .utf8
    )

    #expect(dependencies.contains("func updatePreviewIncomingCommits("))
    #expect(update.contains("try await client.updatePreviewIncomingCommits("))
    #expect(!update.contains("as? any"))
    #expect(!state.contains("UpdatePreviewCommitServing"))
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
    #expect(view.contains(".ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate"))
    #expect(view.contains("preview.canRunUpdate("))
    #expect(view.contains("UpdatePreviewState.maximumVisibleCommitCount"))
    #expect(
        AppLanguage.korean.localized(.ui.update.showingFirstCommits, 100, 101)
            == "전체 101개 커밋 중 처음 100개만 표시합니다."
    )
    #expect(
        AppLanguage.english.localized(.ui.update.showingFirstCommits, 100, 101)
            == "Showing the first 100 of 101 commits."
    )
    #expect(
        AppLanguage.korean.localized(
            .ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate,
            "네트워크 오류"
        ) == "업데이트 미리보기 전체를 불러오지 못했습니다. 그래도 업데이트를 시도할 수 있습니다.\n\n네트워크 오류"
    )
}

@Test func updatePreviewStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.update.showingFirstCommits",
        "ui.update.completeUpdatePreviewCouldNotLoadedCanStillTryUpdate",
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

@MainActor
private func makeUpdatePreviewFailureStore(
    project: SVNProject,
    error: Error,
    mode: UpdatePreviewFailureMode = .remoteOnly
) -> ProjectStore {
    ProjectStore(
        credentialStore: UpdatePreviewFailingCredentialStore(error: error),
        persistence: UpdatePreviewProjectPersistence(projects: [project]),
        isDemoMode: mode == .remoteOnly,
        updateBadgeRefreshInterval: nil
    )
}

private enum UpdatePreviewFailureMode {
    case remoteOnly
    case incomingAndRemote
}

private final class UpdatePreviewFailingCredentialStore: CredentialStoring {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func password(for _: UUID) throws -> String? {
        throw error
    }

    func setPassword(_: String, for _: UUID) throws {
        throw error
    }

    func deletePassword(for _: UUID) throws {
        throw error
    }
}

private final class UpdatePreviewProjectPersistence: ProjectPersisting {
    let projects: [SVNProject]

    init(projects: [SVNProject]) {
        self.projects = projects
    }

    func loadProjects() -> [SVNProject] {
        projects
    }

    func saveProjects(_: [SVNProject]) {}
}

@Test func updatePreviewTreatsRejectedCommitAsOutOfDateWorkingCopy() {
    #expect(UpdatePreviewCommitRecoveryPolicy.treatsWorkingCopyAsOutOfDate(
        hasCommitRecovery: true,
        isWorkingCopyOutOfDate: nil
    ))
    #expect(UpdatePreviewCommitRecoveryPolicy.treatsWorkingCopyAsOutOfDate(
        hasCommitRecovery: true,
        isWorkingCopyOutOfDate: false
    ))
    #expect(UpdatePreviewCommitRecoveryPolicy.treatsWorkingCopyAsOutOfDate(
        hasCommitRecovery: false,
        isWorkingCopyOutOfDate: true
    ))
    #expect(!UpdatePreviewCommitRecoveryPolicy.treatsWorkingCopyAsOutOfDate(
        hasCommitRecovery: false,
        isWorkingCopyOutOfDate: false
    ))
}

@Test func updatePreviewRunsUpdateWhenOnlyCommitRejectionKnown() {
    let state = UpdatePreviewState()
    #expect(state.canRunUpdate(hasRemoteChanges: false, isWorkingCopyOutOfDate: true))
    #expect(!state.canRunUpdate(hasRemoteChanges: false, isWorkingCopyOutOfDate: false))
}
