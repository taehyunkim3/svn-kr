import Foundation
import SVNCore
import Testing
@testable import SVNMac

@MainActor
@Test func conflictFileErrorsUseRequestedLanguageAtStoreBoundary() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/project")])

    #expect(store.localizedError(ConflictFileError.missingWorkingFile, language: .korean) == "현재 작업 파일을 찾을 수 없습니다.")
    #expect(store.localizedError(ConflictFileError.missingWorkingFile, language: .english) == "The current working file could not be found.")
    #expect(store.localizedError(ConflictFileError.unsupportedType("tree"), language: .english) == "Unsupported conflict type: tree")
    #expect(store.localizedError(SVNError.invalidWorkingCopy, language: .korean) == "선택한 폴더는 SVN 로컬 작업 폴더가 아닙니다.")
    #expect(store.localizedError(SVNError.invalidWorkingCopy, language: .english) == "The selected folder is not an SVN local working folder.")
}

@MainActor
@Test func latestRequestTrackerRejectsOlderAndSwitchedProjectResults() {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/request-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/request-second")
    let store = makeStore(projects: [first, second])

    let older = store.beginRequest(.fileTree)
    let latest = store.beginRequest(.fileTree)
    #expect(!store.canApplyRequest(older, kind: .fileTree, projectID: first.id))
    #expect(store.canApplyRequest(latest, kind: .fileTree, projectID: first.id))

    store.selectedProjectID = second.id
    #expect(!store.canApplyRequest(latest, kind: .fileTree, projectID: first.id))
}

@MainActor
@Test func repositoryPathNormalizationDoesNotScanAutomatically() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/no-automatic-normalization")
    let client = StubSVNClient(
        repositoryPathNormalizationTargets: [
            makeRepositoryPathNormalizationTarget("문서/한글 안내.md")
        ]
    )
    _ = makeStore(projects: [project], client: client)

    #expect(await client.repositoryPathNormalizationScanRequestCount() == 0)
}

@Test func repositoryPathNormalizationIssuesHaveKoreanAndEnglishGuidance() {
    let target = makeRepositoryPathNormalizationTarget("문서/실패.md")
    let partialResult = SVNRepositoryPathNormalizationResult(
        renamedTargets: [makeRepositoryPathNormalizationTarget("문서/완료.md")],
        skippedTargets: [],
        committedRevisions: ["41"]
    )
    let issues = [
        RepositoryPathNormalizationIssue(
            kind: .blockedByLocalChanges,
            paths: ["로컬.txt"], result: nil, failedTarget: nil, details: nil
        ),
        RepositoryPathNormalizationIssue(
            kind: .blockedByLocks,
            paths: ["잠김.txt"], result: nil, failedTarget: nil, details: nil
        ),
        RepositoryPathNormalizationIssue(
            kind: .invalidTargets,
            paths: ["무효.txt"], result: nil, failedTarget: nil, details: nil
        ),
        RepositoryPathNormalizationIssue(
            kind: .partiallyFailed,
            paths: [target.repositoryPath],
            result: partialResult,
            failedTarget: target,
            details: "server move failed"
        ),
    ]

    for issue in issues {
        #expect(!issue.localizedMessage(.korean).isEmpty)
        #expect(!issue.localizedMessage(.english).isEmpty)
        #expect(issue.localizedMessage(.korean) != issue.localizedMessage(.english))
    }
    #expect(issues[0].localizedMessage(.korean).contains("커밋"))
    #expect(issues[1].localizedMessage(.english).contains("Release the locks"))
    #expect(issues[2].localizedMessage(.korean).contains("유효하지"))
    #expect(issues[3].localizedMessage(.english).contains("already committed"))
    #expect(issues[3].localizedMessage(.korean).contains("남은 경로부터"))
}

@MainActor
@Test func emptyRepositoryPathNormalizationScanNeverOpensReviewAndShowsNotice() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/empty-normalization")
    let scanGate = AsyncTestGate()
    let client = StubSVNClient(repositoryPathNormalizationScanGate: scanGate)
    let store = makeStore(projects: [project], client: client)

    let scanTask = Task { await store.beginRepositoryPathNormalization() }
    for _ in 0..<100 {
        if await client.repositoryPathNormalizationScanRequestCount() == 1 { break }
        await Task.yield()
    }

    #expect(!store.isShowingRepositoryPathNormalization)
    #expect(store.isScanningRepositoryPaths)

    await scanGate.release()
    await scanTask.value

    #expect(await client.repositoryPathNormalizationScanRequestCount() == 1)
    #expect(store.repositoryPathNormalizationTargets.isEmpty)
    #expect(store.selectedRepositoryPathNormalizationTargets.isEmpty)
    #expect(!store.isShowingRepositoryPathNormalization)
    #expect(store.notice != nil)
}

@MainActor
@Test func failedRepositoryPathNormalizationScanExposesErrorWithoutOpeningReview() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/failed-normalization")
    let client = StubSVNClient(
        repositoryPathNormalizationScanError: TestError.repositoryPathNormalizationScanFailed
    )
    let store = makeStore(projects: [project], client: client)

    await store.beginRepositoryPathNormalization()

    #expect(await client.repositoryPathNormalizationScanRequestCount() == 1)
    #expect(!store.isShowingRepositoryPathNormalization)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func repositoryPathNormalizationScanSelectsAllAndSupportsSelectionToggles() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/normalization-selection")
    let targets = [
        makeRepositoryPathNormalizationTarget("문서/한글 안내.md"),
        makeRepositoryPathNormalizationTarget("자료/제품 화면", isDirectory: true),
    ]
    let scanGate = AsyncTestGate()
    let client = StubSVNClient(
        repositoryPathNormalizationTargets: targets,
        repositoryPathNormalizationScanGate: scanGate
    )
    let store = makeStore(projects: [project], client: client)

    let scanTask = Task { await store.beginRepositoryPathNormalization() }
    for _ in 0..<100 {
        if await client.repositoryPathNormalizationScanRequestCount() == 1 { break }
        await Task.yield()
    }
    #expect(!store.isShowingRepositoryPathNormalization)
    #expect(store.isScanningRepositoryPaths)
    #expect(store.repositoryPathNormalizationTargets.isEmpty)

    await scanGate.release()
    await scanTask.value

    #expect(!store.isScanningRepositoryPaths)
    #expect(store.isShowingRepositoryPathNormalization)
    #expect(store.repositoryPathNormalizationTargets == targets)
    #expect(store.selectedRepositoryPathNormalizationTargets == Set(targets))
    #expect(store.allRepositoryPathNormalizationTargetsAreSelected)

    store.toggleRepositoryPathNormalizationTarget(targets[0])
    #expect(!store.selectedRepositoryPathNormalizationTargets.contains(targets[0]))
    #expect(!store.allRepositoryPathNormalizationTargetsAreSelected)

    store.setAllRepositoryPathNormalizationTargetsSelected(false)
    #expect(store.selectedRepositoryPathNormalizationTargets.isEmpty)
    store.setAllRepositoryPathNormalizationTargetsSelected(true)
    #expect(store.selectedRepositoryPathNormalizationTargets == Set(targets))
}

@MainActor
@Test func repositoryPathNormalizationExposesLocalChangeBlockingPaths() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/normalization-local-block")
    let target = makeRepositoryPathNormalizationTarget("문서/한글 안내.md")
    let blockingPaths = ["Sources/작업 중.swift", "Docs/메모.md"]
    let client = StubSVNClient(
        repositoryPathNormalizationTargets: [target],
        repositoryPathNormalizationError: .blockedByLocalChanges(paths: blockingPaths)
    )
    let store = makeStore(projects: [project], client: client)

    await store.beginRepositoryPathNormalization()
    store.requestRepositoryPathNormalizationConfirmation()
    await store.normalizeSelectedRepositoryPaths()

    #expect(store.repositoryPathNormalizationIssue?.kind == .blockedByLocalChanges)
    #expect(store.repositoryPathNormalizationIssue?.paths == blockingPaths)
    #expect(await client.repositoryPathNormalizationRequestCount() == 1)
    #expect(await client.updateRequestCount() == 0)
}

@MainActor
@Test func repositoryPathNormalizationExposesLockBlockingPaths() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/normalization-lock-block")
    let target = makeRepositoryPathNormalizationTarget("문서/한글 안내.md")
    let blockingPaths = ["문서/잠긴 안내.md"]
    let client = StubSVNClient(
        repositoryPathNormalizationTargets: [target],
        repositoryPathNormalizationError: .blockedByLocks(paths: blockingPaths)
    )
    let store = makeStore(projects: [project], client: client)

    await store.beginRepositoryPathNormalization()
    store.requestRepositoryPathNormalizationConfirmation()
    await store.normalizeSelectedRepositoryPaths()

    #expect(store.repositoryPathNormalizationIssue?.kind == .blockedByLocks)
    #expect(store.repositoryPathNormalizationIssue?.paths == blockingPaths)
    #expect(await client.updateRequestCount() == 0)
}

@MainActor
@Test func repositoryPathNormalizationPreservesPartialSuccessAndUpdatesWorkingCopy() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/normalization-partial")
    let succeeded = makeRepositoryPathNormalizationTarget("문서/완료.md")
    let failed = makeRepositoryPathNormalizationTarget("문서/실패.md")
    let partialResult = SVNRepositoryPathNormalizationResult(
        renamedTargets: [succeeded],
        skippedTargets: [],
        committedRevisions: ["41"]
    )
    let client = StubSVNClient(
        repositoryPathNormalizationTargets: [succeeded, failed],
        repositoryPathNormalizationError: .failed(
            result: partialResult,
            failedTarget: failed,
            details: "server move failed"
        )
    )
    let store = makeStore(projects: [project], client: client)

    await store.beginRepositoryPathNormalization()
    store.requestRepositoryPathNormalizationConfirmation()
    await store.normalizeSelectedRepositoryPaths()

    #expect(store.repositoryPathNormalizationIssue?.kind == .partiallyFailed)
    #expect(store.repositoryPathNormalizationIssue?.result?.renamedTargets.count == 1)
    #expect(store.repositoryPathNormalizationResult?.renamedTargets.count == 1)
    #expect(store.repositoryPathNormalizationIssue?.failedTarget == failed)
    #expect(await client.updateRequestCount() == 1)
}

@MainActor
@Test func successfulRepositoryPathNormalizationUpdatesWorkingCopy() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/normalization-success")
    let target = makeRepositoryPathNormalizationTarget("문서/한글 안내.md")
    let result = SVNRepositoryPathNormalizationResult(
        renamedTargets: [target],
        skippedTargets: [],
        committedRevisions: ["42"]
    )
    let client = StubSVNClient(
        repositoryPathNormalizationTargets: [target],
        repositoryPathNormalizationResult: result
    )
    let store = makeStore(projects: [project], client: client)

    await store.beginRepositoryPathNormalization()
    store.requestRepositoryPathNormalizationConfirmation()
    await store.normalizeSelectedRepositoryPaths()

    #expect(store.repositoryPathNormalizationResult?.renamedTargets.count == 1)
    #expect(store.repositoryPathNormalizationIssue == nil)
    #expect(await client.repositoryPathNormalizationRequestCount() == 1)
    #expect(await client.updateRequestCount() == 1)
}

@MainActor
@Test func removingCapturedProjectKeepsANewerSelection() {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/remove-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/remove-second")
    let store = makeStore(projects: [first, second])
    store.selectedProjectID = second.id

    store.removeProject(first.id)

    #expect(store.projects.map(\.id) == [second.id])
    #expect(store.selectedProjectID == second.id)
}

@MainActor
@Test func confirmRevertUsesCapturedRequestAfterPresentationStateClears() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/revert-race")
    let entry = SVNStatusEntry(path: "00 사업관리/보고서.hwp", item: .modified)
    let client = StubSVNClient(
        snapshotsByPath: [
            project.path: SVNWorkingCopySnapshot(
                statuses: [],
                revision: SVNWorkingCopyRevision(minimum: "10", maximum: "10"),
                collisions: [],
                versionedPathsByCanonicalKey: [:]
            ),
        ]
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = [entry]
    store.selectedPaths = [entry.path]
    let request = RevertRequest(entry: entry)
    store.revertRequest = nil

    await store.confirmRevert(request)

    #expect(await client.requestedReverts() == [
        RevertCall(workingCopyPath: project.path, relativePath: entry.path),
    ])
    #expect(store.statuses.isEmpty)
    #expect(store.selectedPaths.isEmpty)
}

@MainActor
@Test func staleRevertCompletionDoesNotMutateNewProject() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/revert-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/revert-second")
    let entry = SVNStatusEntry(path: "보고서.hwp", item: .modified)
    let client = StubSVNClient(delaysByPath: [first.path: .milliseconds(100)])
    let store = makeStore(projects: [first, second], client: client)
    store.selectedPaths = [entry.path]

    let task = Task { await store.confirmRevert(RevertRequest(entry: entry)) }
    try? await Task.sleep(for: .milliseconds(10))
    store.selectedProjectID = second.id
    store.notice = "둘째 프로젝트 알림"
    await task.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.notice == "둘째 프로젝트 알림")
}

@MainActor
@Test func staleUpdatePreviewDoesNotPublishChanges() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/update-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/update-second")
    let change = SVNStatusEntry(path: "서버변경.txt", item: .modified)
    let client = StubSVNClient(
        delaysByPath: [first.path: .milliseconds(100)],
        remoteChangesByPath: [first.path: [change]]
    )
    let store = makeStore(projects: [first, second], client: client)

    let task = Task { await store.previewUpdate() }
    try? await Task.sleep(for: .milliseconds(10))
    store.selectedProjectID = second.id
    await task.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.remoteChanges.isEmpty)
    #expect(!store.isShowingUpdatePreview)
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func staleFileHistoryDoesNotOpenOnNewProject() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/history-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/history-second")
    let client = StubSVNClient(
        delaysByPath: [first.path: .milliseconds(100)],
        fileLogsByPath: [first.path: [makeLog(revision: "42")]]
    )
    let store = makeStore(projects: [first, second], client: client)

    let task = Task { await store.loadFileHistory(for: "보고서.hwp") }
    try? await Task.sleep(for: .milliseconds(10))
    store.selectedProjectID = second.id
    await task.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.fileHistory.isEmpty)
    #expect(store.fileHistoryPath == nil)
    #expect(!store.isShowingFileHistory)
}

@MainActor
@Test func preparesBackupsOpensOnlyCopiesAndResolvesSelectedWholeVersion() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot),
        workspaceOpener: opener
    )

    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)
    store.openConflictVersion(.mineFull)
    store.openConflictVersion(.theirsFull)
    store.openConflictBackupFolder()

    #expect(opener.openedURLs == [session.mine.url, session.server.url, session.directoryURL])
    #expect(await client.lastConflictChoice() == nil)
    await store.resolveActiveConflict(using: .theirsFull)

    #expect(await client.lastConflictChoice() == .theirsFull)
    #expect(store.activeConflictSession == nil)
}

@MainActor
@Test func canonicalAliasConflictUsesExactVersionedPathForInfoAndResolve() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let versionedPath = "문서/주간보고서.hwp"
    let selectedPath = versionedPath.decomposedStringWithCanonicalMapping
    let details = try fixture.makeAdditionalConflict(path: versionedPath, stem: "weekly")
    let snapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: versionedPath, item: .conflicted, revision: "42")],
        revision: SVNWorkingCopyRevision(minimum: "42", maximum: "42"),
        collisions: [],
        versionedPathsByCanonicalKey: [versionedPath: [versionedPath]]
    )
    let resolvedSnapshot = SVNWorkingCopySnapshot(
        statuses: [],
        revision: snapshot.revision,
        collisions: [],
        versionedPathsByCanonicalKey: [versionedPath: [versionedPath]]
    )
    let client = StubSVNClient(
        snapshotsByPath: [fixture.project.path: snapshot],
        postResolveSnapshotsByPath: [fixture.project.path: resolvedSnapshot],
        conflictDetailsByRelativePath: [versionedPath: details]
    )
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: selectedPath)

    #expect(await client.exactConflictDetailsRequestCount(for: versionedPath) == 1)
    #expect(await client.exactConflictDetailsRequestCount(for: selectedPath) == 0)
    #expect(store.activeConflictSession != nil)

    await store.resolveActiveConflict(using: .theirsFull)

    #expect(await client.lastResolvedPath().map { Data($0.utf8) } == Data(versionedPath.utf8))
}

@MainActor
@Test func workingFileEditAfterPreparationIsBackedUpBeforeResolve() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)
    let latestBytes = Data([0x6E, 0x65, 0x77, 0x00, 0xFF])
    try latestBytes.write(to: fixture.workingFileURL)

    await store.resolveActiveConflict(using: .mineFull)

    let recoveryURLs = try workingRecoveryURLs(in: session.directoryURL)
    #expect(recoveryURLs.count == 1)
    let recoveryURL = try #require(recoveryURLs.first)
    #expect(try Data(contentsOf: recoveryURL) == latestBytes)
    #expect(await client.lastConflictChoice() == .mineFull)
}

@MainActor
@Test func binaryMineResolveFailureRetryKeepsFirstUserRecovery() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let binaryMineBytes = Data([0x42, 0x49, 0x4E, 0x00, 0xFF])
    try binaryMineBytes.write(to: fixture.workingFileURL)
    let details = SVNConflictDetails(
        path: fixture.details.path,
        type: fixture.details.type,
        operation: fixture.details.operation,
        myFile: nil,
        serverFile: fixture.details.serverFile,
        serverRevision: fixture.details.serverRevision
    )
    let client = StubSVNClient(
        conflictDetailsValue: details,
        resolveError: TestError.resolveConflictFailed
    )
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: details.path)
    let session = try #require(store.activeConflictSession)
    let latestUserBytes = Data([0x55, 0x53, 0x45, 0x52, 0x00, 0xFE])
    try latestUserBytes.write(to: fixture.workingFileURL)

    await store.resolveActiveConflict(using: .mineFull)
    let firstRecoveryURLs = try workingRecoveryURLs(in: session.directoryURL)
    #expect(firstRecoveryURLs.count == 1)
    let firstRecoveryURL = try #require(firstRecoveryURLs.first)
    #expect(try Data(contentsOf: firstRecoveryURL) == latestUserBytes)

    await store.resolveActiveConflict(using: .mineFull)

    let recoveryURLs = try workingRecoveryURLs(in: session.directoryURL)
    #expect(recoveryURLs.count == 2)
    #expect(FileManager.default.fileExists(atPath: firstRecoveryURL.path))
    #expect(try Data(contentsOf: firstRecoveryURL) == latestUserBytes)
    #expect(try recoveryURLs.map { try Data(contentsOf: $0) }.contains(binaryMineBytes))
    #expect(store.activeConflictSession == session)
    #expect(await client.conflictChoiceCount() == 2)
}

@MainActor
@Test func successfulConflictResolveKeepsResolutionNoticeAfterRefresh() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: fixture.details.path)

    await store.resolveActiveConflict(using: .theirsFull)

    #expect(
        store.notice
            == AppLanguage.current.localized(
                "ui.the.conflict.was.resolved.review.the.file.before.7821924b"
            )
    )
}

@MainActor
@Test func resolveKeepsSessionWhenConflictRemainsAfterCommandSuccess() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let conflictedSnapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: fixture.details.path, item: .conflicted, revision: "42")],
        revision: SVNWorkingCopyRevision(minimum: "42", maximum: "42"),
        collisions: [],
        versionedPathsByCanonicalKey: [fixture.details.path: [fixture.details.path]]
    )
    let client = StubSVNClient(
        snapshotsByPath: [fixture.project.path: conflictedSnapshot],
        postResolveSnapshotsByPath: [fixture.project.path: conflictedSnapshot],
        conflictDetailsValue: fixture.details
    )
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)

    await store.resolveActiveConflict(using: .theirsFull)

    #expect(store.activeConflictSession == session)
    #expect(store.errorMessage != nil)
    #expect(store.notice == nil)
}

@MainActor
@Test func failedWorkingRecoveryPreventsResolveAndKeepsSession() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    var copyCount = 0
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(
            backupRootURL: fixture.backupRoot,
            copyItem: { source, destination in
                copyCount += 1
                if copyCount == 3 { throw TestError.backupFailed }
                try FileManager.default.copyItem(at: source, to: destination)
            }
        )
    )
    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)

    await store.resolveActiveConflict(using: .theirsFull)

    #expect(store.activeConflictSession == session)
    #expect(await client.conflictChoiceCount() == 0)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func unsupportedConflictDoesNotCreateResolutionSession() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details(replacingTypeWith: "tree"))
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: fixture.details.path)

    #expect(store.activeConflictSession == nil)
}

@MainActor
@Test func failedBackupDoesNotCreateResolutionSession() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(
            backupRootURL: fixture.backupRoot,
            copyItem: { _, _ in throw TestError.backupFailed }
        )
    )

    await store.prepareConflictResolution(for: fixture.details.path)

    #expect(store.activeConflictSession == nil)
}

@MainActor
@Test func switchingProjectsClearsActiveConflictSession() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let otherProject = SVNProject(name: "다른 프로젝트", path: fixture.root.appendingPathComponent("other").path)
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project, otherProject],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: fixture.details.path)
    #expect(store.activeConflictSession != nil)
    store.selectedProjectID = otherProject.id

    #expect(store.activeConflictSession == nil)
}

@MainActor
@Test func failedResolveKeepsConflictSession() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details, resolveError: TestError.resolveConflictFailed)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)
    await store.resolveActiveConflict(using: .mineFull)

    #expect(store.activeConflictSession == session)
    #expect(await client.lastConflictChoice() == .mineFull)
    #expect(FileManager.default.fileExists(atPath: session.mine.url.path))
    #expect(FileManager.default.fileExists(atPath: session.server.url.path))
}

@MainActor
@Test func workingChoicePreservesLatestBytesAndResolvesConflict() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: fixture.details.path)
    let session = try #require(store.activeConflictSession)
    let latestBytes = Data([0x48, 0x57, 0x50, 0x00, 0xFE])
    try latestBytes.write(to: fixture.workingFileURL)
    await store.resolveActiveConflict(using: .working)

    let recoveryURLs = try workingRecoveryURLs(in: session.directoryURL)
    #expect(store.activeConflictSession == nil)
    #expect(await client.lastConflictChoice() == .working)
    #expect(try recoveryURLs.map { try Data(contentsOf: $0) }.contains(latestBytes))
}

@MainActor
@Test func delayedConflictPreparationDoesNotAssignSessionAfterProjectSwitch() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let otherProject = SVNProject(name: "다른 프로젝트", path: fixture.root.appendingPathComponent("other").path)
    let client = StubSVNClient(
        delaysByPath: [fixture.project.path: .milliseconds(150)],
        conflictDetailsValue: fixture.details
    )
    let store = makeStore(
        projects: [fixture.project, otherProject],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    let preparation = Task { await store.prepareConflictResolution(for: fixture.details.path) }
    try await Task.sleep(for: .milliseconds(20))
    store.selectedProjectID = otherProject.id
    await preparation.value
    await store.resolveActiveConflict(using: .mineFull)

    #expect(store.selectedProjectID == otherProject.id)
    #expect(store.activeConflictSession == nil)
    #expect(await client.lastConflictChoice() == nil)
}

@MainActor
@Test func newerPreparationWinsOverOlderRequestInSameProject() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let olderDetails = fixture.details
    let newerDetails = try fixture.makeAdditionalConflict(path: "Documents/newer.txt", stem: "newer")
    let olderGate = AsyncTestGate()
    let client = StubSVNClient(
        conflictDetailsByRelativePath: [
            olderDetails.path: olderDetails,
            newerDetails.path: newerDetails,
        ],
        conflictDetailsGatesByRelativePath: [olderDetails.path: olderGate]
    )
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    let olderPreparation = Task { await store.prepareConflictResolution(for: olderDetails.path) }
    await waitForConflictDetailsRequest(client, path: olderDetails.path)
    await store.prepareConflictResolution(for: newerDetails.path)
    let newerSessionID = try #require(store.activeConflictSession?.id)
    #expect(store.activeConflictSession?.details.path == newerDetails.path)
    await olderGate.release()
    await olderPreparation.value

    #expect(store.activeConflictSession?.id == newerSessionID)
    #expect(store.activeConflictSession?.details.path == newerDetails.path)
}

@MainActor
@Test func resolveCompletionAfterProjectSwitchDoesNotMutateOrRefreshNewProject() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let otherProject = SVNProject(name: "다른 프로젝트", path: fixture.root.appendingPathComponent("other").path)
    let resolveGate = AsyncTestGate()
    let client = StubSVNClient(conflictDetailsValue: fixture.details, resolveGate: resolveGate)
    let store = makeStore(
        projects: [fixture.project, otherProject],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: fixture.details.path)

    let resolution = Task { await store.resolveActiveConflict(using: .mineFull) }
    await waitForResolveRequest(client)
    store.selectedProjectID = otherProject.id
    store.errorMessage = "new-project-error"
    store.notice = "new-project-notice"
    let snapshotRequestsBeforeCompletion = await client.snapshotRequestCount()
    await resolveGate.release()
    await resolution.value

    #expect(store.selectedProjectID == otherProject.id)
    #expect(store.errorMessage == "new-project-error")
    #expect(store.notice == "new-project-notice")
    #expect(await client.snapshotRequestCount() == snapshotRequestsBeforeCompletion)
}

@MainActor
@Test func oldResolveCompletionDoesNotClearOrRefreshNewerSession() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let resolveGate = AsyncTestGate()
    let client = StubSVNClient(conflictDetailsValue: fixture.details, resolveGate: resolveGate)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: fixture.details.path)
    let firstSessionID = try #require(store.activeConflictSession?.id)

    let oldResolution = Task { await store.resolveActiveConflict(using: .mineFull) }
    await waitForResolveRequest(client)
    await store.prepareConflictResolution(for: fixture.details.path)
    let newerSessionID = try #require(store.activeConflictSession?.id)
    #expect(newerSessionID != firstSessionID)
    let snapshotRequestsBeforeCompletion = await client.snapshotRequestCount()
    await resolveGate.release()
    await oldResolution.value

    #expect(store.activeConflictSession?.id == newerSessionID)
    #expect(store.notice == nil)
    #expect(await client.snapshotRequestCount() == snapshotRequestsBeforeCompletion)
}

@MainActor
@Test func duplicateResolveChoiceIsRejectedWhileSessionIsResolving() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let resolveGate = AsyncTestGate()
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient(conflictDetailsValue: fixture.details, resolveGate: resolveGate)
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot),
        workspaceOpener: opener
    )
    await store.prepareConflictResolution(for: fixture.details.path)

    let first = Task { await store.resolveActiveConflict(using: .mineFull) }
    await waitForResolveRequest(client)
    let duplicate = Task { await store.resolveActiveConflict(using: .theirsFull) }
    for _ in 0..<100 { await Task.yield() }
    store.openConflictVersion(.mineFull)
    store.openConflictVersion(.theirsFull)
    store.openConflictBackupFolder()

    #expect(await client.conflictChoiceCount() == 1)
    #expect(store.isResolvingConflict)
    #expect(opener.openedURLs.isEmpty)
    await resolveGate.release()
    await first.value
    await duplicate.value
}

@MainActor
@Test func staleResolveFailureDoesNotOverwriteNewerSessionErrorOrNotice() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let resolveGate = AsyncTestGate()
    let client = StubSVNClient(
        conflictDetailsValue: fixture.details,
        resolveError: TestError.resolveConflictFailed,
        resolveGate: resolveGate
    )
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )
    await store.prepareConflictResolution(for: fixture.details.path)
    let oldResolution = Task { await store.resolveActiveConflict(using: .mineFull) }
    await waitForResolveRequest(client)
    await store.prepareConflictResolution(for: fixture.details.path)
    let newerSessionID = try #require(store.activeConflictSession?.id)
    store.errorMessage = "newer-error"
    store.notice = "newer-notice"
    let snapshotRequestsBeforeCompletion = await client.snapshotRequestCount()

    await resolveGate.release()
    await oldResolution.value

    #expect(store.activeConflictSession?.id == newerSessionID)
    #expect(store.errorMessage == "newer-error")
    #expect(store.notice == "newer-notice")
    #expect(await client.snapshotRequestCount() == snapshotRequestsBeforeCompletion)
}

@MainActor
@Test func updateCommitBadgeCountsLoadedHistoryAndMarksLowerBounds() {
    let store = makeStore(projects: [])
    store.isWorkingCopyOutOfDate = true
    store.workingCopyRevision = SVNWorkingCopyRevision(minimum: "10", maximum: "10")
    store.logs = [
        makeLog(revision: "14"),
        makeLog(revision: "12"),
        makeLog(revision: "10"),
    ]

    #expect(store.incomingUpdateCommitBadgeText == "2")

    store.hasMoreHistory = true
    store.logs = (11...60).reversed().map { makeLog(revision: String($0)) }
    #expect(store.incomingUpdateCommitBadgeText == "50+")

    store.hasMoreHistory = false
    store.workingCopyRevision = SVNWorkingCopyRevision(minimum: "5", maximum: "10")
    store.logs = [
        makeLog(revision: "12"),
        makeLog(revision: "11"),
        makeLog(revision: "9"),
    ]
    #expect(store.incomingUpdateCommitBadgeText == "2+")

    store.logs = [makeLog(revision: "9")]
    #expect(store.incomingUpdateCommitBadgeText == "1+")

    store.isWorkingCopyOutOfDate = false
    #expect(store.incomingUpdateCommitBadgeText == nil)
}

@MainActor
@Test func changingProjectClearsProjectSpecificViewState() {
    let first = SVNProject(name: "첫 번째", path: "/tmp/first")
    let second = SVNProject(name: "두 번째", path: "/tmp/second")
    let store = makeStore(projects: [first, second])

    store.statuses = [SVNStatusEntry(path: "changed.txt", item: .modified)]
    store.logs = [makeLog(revision: "10")]
    store.selectedPaths = ["changed.txt"]
    store.selectedStatusPath = "changed.txt"
    store.diffContent = .text("diff")
    store.selectedHistoryRevision = "10"
    store.selectedHistoryPath = "/trunk/changed.txt"
    store.historyDiffContent = .text("history diff")
    store.notice = "완료"
    store.errorMessage = "이전 프로젝트 오류"
    store.authenticationRequest = SVNAuthenticationRequest(projectID: first.id, action: .update)

    store.selectedProjectID = second.id

    #expect(store.statuses.isEmpty)
    #expect(store.workingCopyFileTree.isEmpty)
    #expect(store.logs.isEmpty)
    #expect(store.selectedPaths.isEmpty)
    #expect(store.selectedStatusPath == nil)
    #expect(store.diffContent == .placeholder)
    #expect(store.selectedHistoryRevision == nil)
    #expect(store.selectedHistoryPath == nil)
    #expect(store.historyDiffContent == .placeholder)
    #expect(store.notice == nil)
    #expect(store.errorMessage == nil)
    #expect(store.authenticationRequest == nil)
}

@MainActor
@Test func staleFileTreeDoesNotOverwriteNewlySelectedProject() async {
    let first = SVNProject(name: "느린 프로젝트", path: "/tmp/slow-tree")
    let second = SVNProject(name: "빠른 프로젝트", path: "/tmp/fast-tree")
    let fileService = StubWorkingCopyFileService(delaysByPath: [
        first.path: .milliseconds(150),
        second.path: .milliseconds(5),
    ])
    let store = makeStore(projects: [first, second], fileService: fileService)

    let slowLoad = Task { await store.loadWorkingCopyFiles() }
    try? await Task.sleep(for: .milliseconds(20))
    store.selectedProjectID = second.id
    let fastLoad = Task { await store.loadWorkingCopyFiles() }
    await slowLoad.value
    await fastLoad.value

    #expect(store.workingCopyFileTree.map(\.name) == ["fast-tree"])
}

@MainActor
@Test func refreshingFileBrowserClearsExpandedChildCache() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-cache-refresh")
    let store = makeStore(
        projects: [project],
        fileService: StubWorkingCopyFileService(delaysByPath: [:])
    )
    store.workingCopyFileTree = [WorkingCopyFileNode(
        name: "Folder",
        relativePath: "Folder",
        isDirectory: true,
        isSymbolicLink: false,
        svnEntry: nil,
        children: [WorkingCopyFileNode(
            name: "child.txt",
            relativePath: "Folder/child.txt",
            isDirectory: false,
            isSymbolicLink: false,
            svnEntry: nil,
            children: nil
        )]
    )]
    var state = store.workingCopyBrowserTreeState
    state.expandedPaths = ["Folder"]
    store.workingCopyBrowserTreeState = state

    await store.loadWorkingCopyFiles()

    #expect(store.workingCopyBrowserTreeState.childrenByDirectory.isEmpty)
    #expect(store.workingCopyBrowserTreeState.expandedPaths.isEmpty)
}

@MainActor
@Test func unversionedDocumentOpensWithoutRequestingALock() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)

    await store.prepareToOpen(path: "draft.docx", isVersioned: false)

    #expect(opener.openedURLs.map(\.lastPathComponent) == ["draft.docx"])
    #expect(store.documentOpenRequest == nil)
    #expect(await client.lockInfoRequestCount() == 0)
}

@MainActor
@Test func versionedFileOffersLockBeforeOpeningRegardlessOfExtension() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)

    await store.prepareToOpen(path: "README.txt", isVersioned: true)

    #expect(opener.openedURLs.isEmpty)
    #expect(store.documentOpenRequest?.relativePath == "README.txt")
    #expect(await client.lockInfoRequestCount() == 1)
}

@MainActor
@Test func canonicalAliasUsesRepositoryPathForLockAndLocalPathForOpen() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)
    let repositoryPath = "주간보고서.hwp"
    let localPath = repositoryPath.decomposedStringWithCanonicalMapping

    await store.prepareToOpen(
        path: localPath,
        repositoryPath: repositoryPath,
        isVersioned: true,
        isRegularFile: true
    )
    let request = try #require(store.documentOpenRequest)
    await store.lockAndOpen(request)

    #expect(await client.requestedLockInfoPaths() == [repositoryPath])
    #expect(await client.requestedLockPaths() == [repositoryPath])
    #expect(opener.openedURLs.map { Data($0.lastPathComponent.utf8) } == [Data(localPath.utf8)])
}

@MainActor
@Test func versionedNonRegularItemOpensWithoutRequestingALock() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)

    await store.prepareToOpen(path: "Assets.bundle", isVersioned: true, isRegularFile: false)

    #expect(opener.openedURLs.map(\.lastPathComponent) == ["Assets.bundle"])
    #expect(store.documentOpenRequest == nil)
    #expect(await client.lockInfoRequestCount() == 0)
}

@MainActor
@Test func documentAlreadyLockedByCurrentUserOpensImmediately() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project", username: "tester")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient(lockInfoByPath: [
        "plan.pptx": SVNLockInfo(path: "plan.pptx", owner: "tester"),
    ])
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)

    await store.prepareToOpen(path: "plan.pptx", isVersioned: true)

    #expect(opener.openedURLs.map(\.lastPathComponent) == ["plan.pptx"])
    #expect(store.documentOpenRequest == nil)
}

@MainActor
@Test func lockInfoFailureStillOffersOpenWithoutLock() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient(lockInfoError: TestError.lockInfoFailed)
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)

    await store.prepareToOpen(path: "report.xlsx", isVersioned: true)

    let request = try #require(store.documentOpenRequest)
    #expect(store.errorMessage == nil)
    #expect(store.notice == "잠금 정보를 확인하지 못했습니다. 잠그지 않고 파일을 열 수 있습니다.")

    store.openWithoutLock(request)

    #expect(opener.openedURLs.map(\.lastPathComponent) == ["report.xlsx"])
}

@MainActor
@Test func staleRefreshDoesNotOverwriteNewlySelectedProject() async {
    let first = SVNProject(name: "느린 프로젝트", path: "/tmp/slow")
    let second = SVNProject(name: "빠른 프로젝트", path: "/tmp/fast")
    let client = StubSVNClient(
        statusesByPath: [
            first.path: [SVNStatusEntry(path: "slow.txt", item: .modified)],
            second.path: [SVNStatusEntry(path: "fast.txt", item: .added)],
        ],
        revisionsByPath: [first.path: "1", second.path: "2"],
        delaysByPath: [first.path: .milliseconds(150), second.path: .milliseconds(5)]
    )
    let store = makeStore(projects: [first, second], client: client)

    let slowRefresh = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(20))
    store.selectedProjectID = second.id
    let fastRefresh = Task { await store.refresh() }
    await slowRefresh.value
    await fastRefresh.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.statuses.map(\.path) == ["fast.txt"])
    #expect(store.workingCopyRevision == SVNWorkingCopyRevision(minimum: "2", maximum: "2"))
    #expect(!store.isWorking)
}

@MainActor
@Test func refreshPublishesPathCollisionAndDropsUnsafeSelection() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/unicode-collision")
    let collision = SVNPathCollision(
        canonicalPath: "04 구현",
        rawPaths: ["04 구현", "04 구현".decomposedStringWithCanonicalMapping],
        affectedEntryCount: 17_361
    )
    let snapshot = SVNWorkingCopySnapshot(
        statuses: [
            SVNStatusEntry(path: "00 사업관리/보고서.hwp", item: .modified, revision: "13302"),
            SVNStatusEntry(path: "04 구현/취소된추가", item: .missing, revision: "-1"),
        ],
        revision: SVNWorkingCopyRevision(minimum: "13302", maximum: "13302"),
        collisions: [collision],
        versionedPathsByCanonicalKey: [:]
    )
    let client = StubSVNClient(snapshotsByPath: [project.path: snapshot])
    let store = makeStore(projects: [project], client: client)
    store.selectedPaths = ["00 사업관리/보고서.hwp", "04 구현/취소된추가"]

    await store.refresh()

    #expect(store.statuses.map(\.path) == ["00 사업관리/보고서.hwp", "04 구현/취소된추가"])
    #expect(store.pathCollisions.map(\.displayPath) == ["04 구현"])
    #expect(store.selectedPaths == ["00 사업관리/보고서.hwp"])
    #expect(store.selectableStatusPaths == ["00 사업관리/보고서.hwp"])
    #expect(!store.canCommitSelectedPaths)
}

@MainActor
@Test func repairablePathCollisionsKeepAutomaticCommitRepairReachable() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/repairable-commit")])
    store.statuses = [SVNStatusEntry(path: "04 구현/수정.bin", item: .modified)]
    store.selectedPaths = ["04 구현/수정.bin"]
    store.pathCollisions = [makePathCollision(path: "04 구현", repairable: true)]

    #expect(store.canRepairCanonicalAliases)
    #expect(store.canCommitSelectedPaths)
}

@MainActor
@Test func localWorkingCopyRefreshUpdatesStatusWithoutRemoteHistoryRequests() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/local-refresh")
    let entry = SVNStatusEntry(path: "보고서.xlsx", item: .modified, revision: "12")
    let revision = SVNWorkingCopyRevision(minimum: "12", maximum: "12")
    let client = StubSVNClient(
        snapshotsByPath: [
            project.path: SVNWorkingCopySnapshot(
                statuses: [entry],
                revision: revision,
                collisions: [],
                versionedPathsByCanonicalKey: [entry.path: [entry.path]]
            ),
        ]
    )
    let store = makeStore(projects: [project], client: client)
    store.isWorkingCopyOutOfDate = true
    store.isShowingPathRecovery = true
    store.pathRecoveryPreview = SVNRecoveryPreview(
        mappings: [],
        ignoredAliasCount: 7,
        blockingPaths: ["중복 경로"]
    )
    store.pathRecoverySourceProjectID = project.id

    await store.refreshLocalWorkingCopy()

    #expect(store.statuses == [entry])
    #expect(store.workingCopyRevision == revision)
    #expect(store.isWorkingCopyOutOfDate == true)
    #expect(store.isShowingPathRecovery)
    #expect(store.pathRecoveryPreview?.ignoredAliasCount == 7)
    #expect(store.pathRecoverySourceProjectID == project.id)
    #expect(await client.remoteRefreshRequestCounts() == RemoteRefreshRequestCounts(log: 0, outOfDate: 0))
}

@MainActor
@Test func fullRefreshStillRequestsRemoteHistoryAndOutOfDateState() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/full-refresh")
    let client = StubSVNClient(revisionsByPath: [project.path: "12"])
    let store = makeStore(projects: [project], client: client)

    await store.refresh()

    #expect(await client.remoteRefreshRequestCounts() == RemoteRefreshRequestCounts(log: 1, outOfDate: 1))
}

@MainActor
@Test func mainWindowActivationRefreshLoadsLocalStatusAndFilesWithoutRemoteRequests() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/window-activation")
    let client = StubSVNClient(revisionsByPath: [project.path: "12"])
    let store = makeStore(
        projects: [project],
        client: client,
        fileService: StubWorkingCopyFileService(delaysByPath: [:])
    )

    await store.refreshForMainWindowActivation()

    #expect(await client.snapshotRequestCount() == 1)
    #expect(await client.workingCopyEntriesRequestCount() == 1)
    #expect(await client.repositoryLocksRequestCount() == 0)
    #expect(await client.remoteRefreshRequestCounts() == RemoteRefreshRequestCounts(log: 0, outOfDate: 0))
}

@MainActor
@Test func mainWindowActivationRefreshSkipsWhileAnotherOperationIsRunning() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/window-activation-busy")
    let client = StubSVNClient(revisionsByPath: [project.path: "12"])
    let store = makeStore(
        projects: [project],
        client: client,
        fileService: StubWorkingCopyFileService(delaysByPath: [:])
    )
    let operationID = store.beginOperation(.lock(project.id))

    await store.refreshForMainWindowActivation()

    store.endOperation(operationID)
    #expect(await client.snapshotRequestCount() == 0)
    #expect(await client.workingCopyEntriesRequestCount() == 0)
}

@MainActor
@Test func deletedSelectedFolderReportsOnceAndSkipsRepeatedAutomaticRefreshes() async {
    let project = SVNProject(name: "삭제된 프로젝트", path: "/tmp/deleted-working-copy")
    let client = StubSVNClient()
    let pathChecker = StubProjectPathChecker(directoryExists: false)
    let store = makeStore(
        projects: [project],
        client: client,
        fileService: StubWorkingCopyFileService(delaysByPath: [:]),
        projectPathChecker: pathChecker
    )

    async let projectRefresh: Void = store.refresh()
    async let browserRefresh: Void = store.refreshWorkingCopyBrowser()
    _ = await (projectRefresh, browserRefresh)

    #expect(store.errorMessage?.contains("삭제된 프로젝트") == true)
    #expect(await client.snapshotRequestCount() == 0)
    #expect(await client.workingCopyEntriesRequestCount() == 0)
    #expect(await client.repositoryLocksRequestCount() == 0)

    store.errorMessage = nil
    await store.refreshForMainWindowActivation()
    await store.refreshWorkingCopyBrowser()

    #expect(store.errorMessage == nil)
    #expect(await client.snapshotRequestCount() == 0)
    #expect(await client.workingCopyEntriesRequestCount() == 0)
    #expect(await client.repositoryLocksRequestCount() == 0)

    pathChecker.directoryExists = true
    await store.refreshLocalWorkingCopy()

    #expect(store.errorMessage == nil)
    #expect(await client.snapshotRequestCount() == 1)
}

@MainActor
@Test func persistentAutomaticRefreshFailureWaitsForExplicitRetry() async {
    let project = SVNProject(name: "손상된 프로젝트", path: "/tmp/damaged-working-copy")
    let client = StubSVNClient(
        snapshotError: TestError.automaticRefreshFailed,
        workingCopyEntriesError: TestError.automaticRefreshFailed,
        repositoryLocksErrorsByPath: [
            project.path: TestError.automaticRefreshFailed,
        ]
    )
    let store = makeStore(
        projects: [project],
        client: client,
        fileService: StubWorkingCopyFileService(delaysByPath: [:])
    )

    await store.refreshSelectedProject(manual: false)

    #expect(store.errorMessage != nil)
    #expect(await client.snapshotRequestCount() == 1)
    #expect(await client.workingCopyEntriesRequestCount() == 1)
    #expect(await client.repositoryLocksRequestCount() == 1)

    store.errorMessage = nil
    await store.refreshForMainWindowActivation()
    await store.refreshSelectedProject(manual: false)

    #expect(store.errorMessage == nil)
    #expect(await client.snapshotRequestCount() == 1)
    #expect(await client.workingCopyEntriesRequestCount() == 1)
    #expect(await client.repositoryLocksRequestCount() == 1)

    await store.refreshSelectedProject(manual: true)

    #expect(store.errorMessage != nil)
    #expect(await client.snapshotRequestCount() == 2)
    #expect(await client.workingCopyEntriesRequestCount() == 2)
    #expect(await client.repositoryLocksRequestCount() == 2)
}

@MainActor
@Test func staleRepositoryLockFailureDoesNotAffectNewProject() async {
    let first = SVNProject(name: "느린 프로젝트", path: "/tmp/slow-locks")
    let second = SVNProject(name: "빠른 프로젝트", path: "/tmp/fast-locks")
    let secondLock = SVNLockInfo(path: "current.txt", owner: "second-user")
    let client = StubSVNClient(
        delaysByPath: [first.path: .milliseconds(150)],
        repositoryLocksByPath: [second.path: [secondLock]],
        repositoryLocksErrorsByPath: [
            first.path: TestError.staleRepositoryLocksFailed,
        ]
    )
    let store = makeStore(projects: [first, second], client: client)

    let staleLoad = Task { await store.loadRepositoryLocks() }
    try? await Task.sleep(for: .milliseconds(20))
    store.selectedProjectID = second.id
    await store.loadRepositoryLocks()
    await staleLoad.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.repositoryLocks == [secondLock])
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func contextualSheetsOwnDetailedErrorPresentation() {
    let store = makeStore(projects: [])
    #expect(!store.hasContextualErrorPresentationOwner)

    store.isShowingAddRepository = true
    #expect(store.hasContextualErrorPresentationOwner)
    store.isShowingAddRepository = false

    store.isShowingLocks = true
    #expect(store.hasContextualErrorPresentationOwner)
}

@MainActor
@Test func ambiguousPathCollisionsBlockCommitAndAutomaticCleanup() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/ambiguous-commit")])
    store.statuses = [SVNStatusEntry(path: "04 구현/수정.bin", item: .modified)]
    store.selectedPaths = ["04 구현/수정.bin"]
    store.pathCollisions = [makePathCollision(path: "04 구현", repairable: false)]

    #expect(!store.canRepairCanonicalAliases)
    #expect(!store.canCommitSelectedPaths)
}

@MainActor
@Test func mixedPathCollisionsBlockCommitAndGuaranteedFailCleanup() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/mixed-commit")])
    store.statuses = [SVNStatusEntry(path: "04 구현/수정.bin", item: .modified)]
    store.selectedPaths = ["04 구현/수정.bin"]
    store.pathCollisions = [
        makePathCollision(path: "04 구현", repairable: true),
        makePathCollision(path: "05 배포", repairable: false),
    ]

    #expect(!store.canRepairCanonicalAliases)
    #expect(!store.canCommitSelectedPaths)
}

@MainActor
@Test func completedCommitWarningClearsSelectionRefreshesAndPreventsRetry() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/post-commit-warning")
    let client = StubSVNClient(
        snapshotsByPath: [
            project.path: SVNWorkingCopySnapshot(
                statuses: [],
                revision: SVNWorkingCopyRevision(minimum: "2", maximum: "2"),
                collisions: [],
                versionedPathsByCanonicalKey: [:]
            ),
        ],
        commitCompletedWarning: (
            output: "Committed revision 2.\n",
            details: "04 구현"
        )
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = [SVNStatusEntry(path: "새 파일.bin", item: .unversioned)]
    store.selectedPaths = ["새 파일.bin"]

    let succeeded = await store.commit(message: "완료 후 검증")

    #expect(succeeded)
    #expect(store.selectedPaths.isEmpty)
    #expect(store.lastCompletedCommitMessage == "완료 후 검증")
    #expect(store.notice?.contains("다시 커밋하지") == true)
    #expect(await client.snapshotRequestCount() == 1)
}

@MainActor
@Test func outOfDateCommitMarksUpdateRequiredAndKeepsSelectionForRetry() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/out-of-date-commit")
    let details = """
    svn: E155011: Directory 'generated' is out of date
    svn: E170004: Directory '/trunk/generated' is out of date
    """
    let client = StubSVNClient(
        commitError: .workingCopyOutOfDate(details: details)
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = [SVNStatusEntry(path: "generated", item: .deleted, revision: "13295")]
    store.selectedPaths = ["generated"]
    store.isWorkingCopyOutOfDate = false

    let succeeded = await store.commit(message: "디렉터리 삭제")

    #expect(!succeeded)
    #expect(store.isWorkingCopyOutOfDate == true)
    #expect(store.selectedPaths == ["generated"])
    #expect(store.lastCompletedCommitMessage == nil)
    #expect(store.errorMessage?.contains("E155011") == true)
    #expect(store.localizedError(
        SVNError.workingCopyOutOfDate(details: details),
        language: .english
    ).contains("Run Update") == true)
}

@MainActor
@Test func repairCanonicalAliasesRepairsInPlaceAndDoesNotOpenPathRecovery() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/repairable-unicode-collision")
    let collision = SVNPathCollision(
        canonicalPath: "04 구현",
        rawPaths: ["04 구현", "04 구현".decomposedStringWithCanonicalMapping],
        affectedEntryCount: 17_361,
        repairableRawPath: "04 구현".decomposedStringWithCanonicalMapping
    )
    let repairableSnapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: "04 구현/취소된추가", item: .missing)],
        revision: SVNWorkingCopyRevision(minimum: "13302", maximum: "13302"),
        collisions: [collision],
        versionedPathsByCanonicalKey: [:]
    )
    let repairedSnapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: "04 구현/정상파일", item: .modified)],
        revision: SVNWorkingCopyRevision(minimum: "13302", maximum: "13302"),
        collisions: [],
        versionedPathsByCanonicalKey: [:]
    )
    let client = StubSVNClient(
        snapshotsByPath: [project.path: repairableSnapshot],
        repairedSnapshotsByPath: [project.path: repairedSnapshot]
    )
    let store = makeStore(projects: [project], client: client)

    await store.refresh()
    await store.repairCanonicalAliases()

    #expect(await client.repairRequestCount() == 1)
    #expect(store.statuses.map(\.path) == ["04 구현/정상파일"])
    #expect(!store.isShowingPathRecovery)
    #expect(store.pathCollisions.isEmpty)
}

@MainActor
@Test func overlappingOperationsKeepBusyStateUntilAllFinish() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let client = StubSVNClient(
        statusesByPath: [project.path: []],
        revisionsByPath: [project.path: "1"],
        delaysByPath: [project.path: .milliseconds(80)]
    )
    let store = makeStore(projects: [project], client: client)

    let first = Task { await store.refresh() }
    let second = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isWorking)
    #expect(store.activeOperations.count == 2)
    #expect(store.activeOperations.allSatisfy { $0.kind == .refresh(project.id) })

    await first.value
    await second.value
    #expect(!store.isWorking)
    #expect(store.activeOperations.isEmpty)
}

@MainActor
@Test func historyLoadingTracksOnlySelectedProjectsHistoryOperations() {
    let selectedProject = SVNProject(name: "선택 프로젝트", path: "/tmp/selected")
    let otherProject = SVNProject(name: "다른 프로젝트", path: "/tmp/other")
    let store = makeStore(projects: [selectedProject, otherProject])

    #expect(!store.isHistoryLoading)

    let refreshID = store.beginOperation(.refresh(selectedProject.id))
    #expect(store.isHistoryLoading)
    store.endOperation(refreshID)

    let historyID = store.beginOperation(.refreshHistory(selectedProject.id))
    #expect(store.isHistoryLoading)
    store.endOperation(historyID)

    let localRefreshID = store.beginOperation(.refreshLocal(selectedProject.id))
    #expect(!store.isHistoryLoading)
    store.endOperation(localRefreshID)

    let otherProjectID = store.beginOperation(.refresh(otherProject.id))
    #expect(!store.isHistoryLoading)
    store.endOperation(otherProjectID)

    let diffID = store.beginOperation(.revisionDiff(selectedProject.id))
    #expect(!store.isHistoryLoading)
    store.endOperation(diffID)
}

@MainActor
@Test func commitProgressTracksOnlySelectedProjectsCommit() {
    let selected = SVNProject(name: "선택", path: "/tmp/selected")
    let other = SVNProject(name: "다른", path: "/tmp/other")
    let store = makeStore(projects: [selected, other])

    #expect(!store.isCommittingSelectedProject)
    #expect(!store.showsGlobalProgress)

    let refreshID = store.beginOperation(.refresh(selected.id))
    #expect(!store.isCommittingSelectedProject)
    #expect(store.showsGlobalProgress)
    store.endOperation(refreshID)

    let otherCommitID = store.beginOperation(.commit(other.id))
    #expect(!store.isCommittingSelectedProject)
    #expect(store.showsGlobalProgress)
    store.endOperation(otherCommitID)

    let commitID = store.beginOperation(.commit(selected.id))
    #expect(store.isCommittingSelectedProject)
    #expect(!store.showsGlobalProgress)
    store.endOperation(commitID)
}

@MainActor
@Test func selectedProjectActionsIgnoreUnrelatedReadOperations() {
    let selected = SVNProject(name: "선택", path: "/tmp/selected")
    let other = SVNProject(name: "다른", path: "/tmp/other")
    let store = makeStore(projects: [selected, other])

    let selectedHistoryID = store.beginOperation(.fileHistory(selected.id))
    let otherCommitID = store.beginOperation(.commit(other.id))
    #expect(!store.isSelectedProjectActionBlocked)

    let refreshID = store.beginOperation(.refresh(selected.id))
    #expect(store.isRefreshingSelectedProject)
    #expect(store.isSelectedProjectActionBlocked)
    store.endOperation(refreshID)

    let mutationID = store.beginOperation(.ignore(selected.id))
    #expect(store.isMutatingSelectedProject)
    #expect(store.isSelectedProjectActionBlocked)

    store.endOperation(mutationID)
    store.endOperation(selectedHistoryID)
    store.endOperation(otherCommitID)
    #expect(!store.isSelectedProjectActionBlocked)
}

@MainActor
@Test func checksConflictsInLargeSelection() {
    let statuses = (0..<20_000).map {
        SVNStatusEntry(path: "Sources/file-\($0).swift", item: .modified)
    } + [SVNStatusEntry(path: "Sources/conflict.swift", item: .conflicted)]
    let allowed = Set(statuses.dropLast().map(\.path))

    #expect(!ProjectStore.containsSelectedConflict(selectedPaths: allowed, statuses: statuses))
    #expect(ProjectStore.containsSelectedConflict(
        selectedPaths: ["Sources/conflict.swift"],
        statuses: statuses
    ))
}

@MainActor
@Test func checkoutRemainsSuccessfulWhenCredentialPersistenceFails() async {
    let client = StubSVNClient(checkoutResult: "Checked out revision 10.")
    let credentials = StubCredentialStore(setError: TestError.credentialWriteFailed)
    let persistence = MemoryProjectPersistence()
    let store = ProjectStore(
        client: client,
        credentialStore: credentials,
        persistence: persistence,
        projectAccessManager: StubProjectAccessManager(),
        projectPathChecker: StubProjectPathChecker()
    )
    let destination = URL(fileURLWithPath: "/tmp/checked-out-project", isDirectory: true)

    let succeeded = await store.checkout(
        repositoryURL: "https://example.test/svn/project",
        destinationURL: destination,
        username: "tester",
        password: "secret",
        allowsUntrustedServerCertificate: false
    )

    #expect(succeeded)
    #expect(store.projects.count == 1)
    #expect(store.selectedProject?.path == destination.path)
    #expect(store.notice?.contains("Keychain") == true)
    #expect(persistence.savedProjects.count == 1)
}

@MainActor
@Test func checkoutPublishesReceivedProgress() async {
    let client = StubSVNClient(
        checkoutResult: "Checked out revision 10.\n",
        checkoutProgress: [
            "A    Sources/App.swift\n",
            "A    Sources/ProjectStore.swift\n",
            "Checked out revision 10.\n",
        ]
    )
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(),
        projectAccessManager: StubProjectAccessManager(),
        projectPathChecker: StubProjectPathChecker()
    )

    let succeeded = await store.checkout(
        repositoryURL: "https://example.test/svn/project",
        destinationURL: URL(fileURLWithPath: "/tmp/checkout-progress", isDirectory: true),
        username: "",
        password: "",
        allowsUntrustedServerCertificate: false
    )

    #expect(succeeded)
    #expect(store.checkoutLog == """
    A    Sources/App.swift
    A    Sources/ProjectStore.swift
    Checked out revision 10.

    """)
}

@MainActor
@Test func cancelingCheckoutStopsTheRunAndLeavesNoProjectRegistered() async {
    let client = StubSVNClient(checkoutRunsUntilCancelled: true)
    let accessManager = StubProjectAccessManager()
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(),
        projectAccessManager: accessManager,
        projectPathChecker: StubProjectPathChecker()
    )
    let destination = URL(fileURLWithPath: "/tmp/canceled-checkout", isDirectory: true)

    let checkout = Task {
        await store.startCheckout(
            repositoryURL: "https://example.test/svn/project",
            destinationURL: destination,
            username: "",
            password: "",
            allowsUntrustedServerCertificate: false
        )
    }
    await waitUntilCheckoutStarts(client)
    store.cancelCheckout()
    let succeeded = await checkout.value

    #expect(!succeeded)
    #expect(store.projects.isEmpty)
    #expect(!store.isCheckingOut)
    // 사용자가 직접 멈춘 작업이므로 오류가 아니라 남은 파일 위치 안내만 남깁니다.
    #expect(store.errorMessage == nil)
    #expect(store.notice?.contains(destination.path) == true)
    #expect(accessManager.releasedURLs.contains(destination))
}

@MainActor
@Test func relocatingProjectKeepsIdentityAndCredentialsWhileMovingTheFolder() async {
    let project = SVNProject(name: "이전 폴더", path: "/tmp/old-location", username: "tester")
    let client = StubSVNClient()
    let accessManager = StubProjectAccessManager()
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: accessManager,
        projectPathChecker: StubProjectPathChecker()
    )
    let destination = URL(fileURLWithPath: "/tmp/new-location", isDirectory: true)

    let relocated = await store.relocateProject(project.id, to: destination)

    #expect(relocated)
    #expect(store.projects.count == 1)
    #expect(store.projects.first?.id == project.id)
    #expect(store.projects.first?.path == destination.path)
    #expect(store.projects.first?.name == "new-location")
    #expect(store.projects.first?.username == "tester")
    #expect(await client.recordedValidatedPaths() == [destination.path])
    #expect(accessManager.accessedURLs[project.id] == destination)
}

@MainActor
@Test func invalidCredentialsAreReportedWithoutTouchingStoredSettings() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project", username: "old-user")
    let client = StubSVNClient(
        verifyCredentialsError: SVNError.commandFailed(command: "svn info", message: "E215004")
    )
    let credentials = StubCredentialStore()
    let persistence = MemoryProjectPersistence(projects: [project])
    let store = ProjectStore(
        client: client,
        credentialStore: credentials,
        persistence: persistence,
        projectAccessManager: StubProjectAccessManager(),
        projectPathChecker: StubProjectPathChecker()
    )

    let failure = await store.verifyCredentials(
        for: project.id,
        username: "new-user",
        password: "wrong",
        allowsUntrustedServerCertificate: false
    )

    #expect(failure != nil)
    // 확인 단계에서 실패하면 프로젝트 목록과 Keychain은 그대로여야 되돌릴 것이 없습니다.
    #expect(store.projects.first?.username == "old-user")
    #expect(!store.hasSavedPassword(for: project.id))
    #expect(!store.isVerifyingCredentials)
}

@MainActor
@Test func blankPasswordVerifiesWithTheAlreadyStoredPassword() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project", username: "tester")
    let client = StubSVNClient()
    let credentials = StubCredentialStore()
    let store = ProjectStore(
        client: client,
        credentialStore: credentials,
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: StubProjectAccessManager(),
        projectPathChecker: StubProjectPathChecker()
    )
    #expect(store.saveCredentials(
        for: project.id,
        username: "tester",
        newPassword: "stored-secret",
        allowsUntrustedServerCertificate: false
    ))

    let failure = await store.verifyCredentials(
        for: project.id,
        username: "tester",
        password: "",
        allowsUntrustedServerCertificate: false
    )

    #expect(failure == nil)
    let verified = await client.recordedVerifiedCredentials()
    #expect(verified.count == 1)
    #expect(verified.first??.username == "tester")
    #expect(verified.first??.password == "stored-secret")
}

@MainActor
@Test func relocatingToAFolderRegisteredByAnotherProjectIsRejected() async {
    let first = SVNProject(name: "첫 폴더", path: "/tmp/first-location")
    let second = SVNProject(name: "둘째 폴더", path: "/tmp/second-location")
    let store = makeStore(projects: [first, second])

    let relocated = await store.relocateProject(
        first.id,
        to: URL(fileURLWithPath: second.path, isDirectory: true)
    )

    #expect(!relocated)
    #expect(store.projects.first?.path == first.path)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func failedWorkingCopyValidationKeepsTheOriginalFolderRegistration() async {
    let project = SVNProject(name: "이전 폴더", path: "/tmp/original-location")
    let client = StubSVNClient(validateWorkingCopyError: SVNError.invalidWorkingCopy)
    let accessManager = StubProjectAccessManager()
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: accessManager,
        projectPathChecker: StubProjectPathChecker()
    )

    let relocated = await store.relocateProject(
        project.id,
        to: URL(fileURLWithPath: "/tmp/not-a-working-copy", isDirectory: true)
    )

    #expect(!relocated)
    #expect(store.projects.first?.path == project.path)
    #expect(store.errorMessage != nil)
    // 검증에 실패하면 이전 폴더 접근 권한을 되돌려 다음 새로고침이 계속 동작해야 합니다.
    #expect(accessManager.accessedURLs[project.id] == URL(fileURLWithPath: project.path, isDirectory: true))
}

@MainActor
@Test func recoveryRegistersSideBySideProjectAndKeepsSource() async {
    let source = SVNProject(
        name: "손상 작업본",
        path: "/tmp/corrupted-source",
        username: "tester",
        allowsUntrustedServerCertificate: true
    )
    let preview = SVNRecoveryPreview(
        mappings: [
            SVNRecoveryPathMapping(sourcePath: "기능/수정.txt", destinationPath: "기능/수정.txt", status: .modified),
        ],
        ignoredAliasCount: 17_361,
        blockingPaths: []
    )
    let recoveredSnapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: "기능/수정.txt", item: .modified, revision: "10")],
        revision: SVNWorkingCopyRevision(minimum: "10", maximum: "10"),
        collisions: [],
        versionedPathsByCanonicalKey: [:]
    )
    let client = StubSVNClient(
        recoveryPreview: preview,
        recoveryResult: SVNRecoveryResult(
            destinationPath: "/tmp/recovered-copy",
            snapshot: recoveredSnapshot,
            migratedPaths: ["기능/수정.txt"]
        )
    )
    let store = makeStore(projects: [source], client: client)

    await store.beginPathRecovery()
    #expect(store.isShowingPathRecovery)
    #expect(store.pathRecoveryPreview?.ignoredAliasCount == 17_361)

    let succeeded = await store.recoverWorkingCopy(
        to: URL(fileURLWithPath: "/tmp/recovered-copy", isDirectory: true)
    )

    #expect(succeeded)
    #expect(store.projects.count == 2)
    #expect(store.projects.contains(where: { $0.id == source.id && $0.path == source.path }))
    #expect(store.selectedProject?.path == "/tmp/recovered-copy")
    #expect(store.selectedProject?.username == "tester")
    #expect(store.selectedProject?.allowsUntrustedServerCertificate == true)
    #expect(await client.lastRecoveryPaths() == [source.path, "/tmp/recovered-copy"])
}

@MainActor
@Test func historyDiffLoadsOnlySelectedFileAndUsesPreviousPegForDeletion() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client)
    let deletedPath = SVNChangedPath(path: "/trunk/Old.swift", action: .deleted, kind: .file)

    store.logs = [
        SVNLogEntry(
            revision: "42",
            author: "tester",
            date: nil,
            message: "delete",
            changedPaths: [deletedPath]
        ),
    ]
    store.workingCopyRepositoryPath = "/trunk"
    store.selectHistoryRevision("42")
    await store.loadHistoryDiff(for: "42", changedPath: deletedPath)

    #expect(store.selectedHistoryRevision == "42")
    #expect(store.selectedHistoryPath == "/trunk/Old.swift")
    #expect(store.historyDiffContent == .text("revision diff"))
    #expect(await client.lastRevisionDiffRequest() == RevisionDiffRequest(
        revision: "42",
        repositoryPath: "/trunk/Old.swift",
        workingCopyRepositoryPath: "/trunk",
        pegRevision: "41"
    ))
}

@Test func recognizesTemporaryFileNamesButOnlyHidesKnownUnversionedFiles() {
    let temporaryPaths = [
        "문서/~$보고서.xlsx",
        ".DS_Store",
        "자료/._원본.pdf",
        "코드/.main.swift.swp",
        "코드/.main.swift.swo",
        "메모.txt~",
        "#메모.txt#",
        ".#메모.txt",
    ]

    for path in temporaryPaths {
        let entry = SVNStatusEntry(path: path, item: .unversioned, nodeKind: .file)
        #expect(TemporaryFilePolicy.isTemporaryFile(entry), "임시 파일로 분류되지 않음: \(path)")
    }

    let ordinaryPaths = ["보고서.xlsx", "cache.tmp", "cache.temp", "DS_Store"]
    for path in ordinaryPaths {
        let entry = SVNStatusEntry(path: path, item: .unversioned, nodeKind: .file)
        #expect(!TemporaryFilePolicy.isTemporaryFile(entry), "일반 파일이 임시 파일로 분류됨: \(path)")
    }

    let versioned = SVNStatusEntry(path: "~$관리.xlsx", item: .modified, nodeKind: .file)
    let directory = SVNStatusEntry(path: "~$폴더", item: .unversioned, nodeKind: .directory)
    let unknownKind = SVNStatusEntry(path: "~$종류미상", item: .unversioned)

    #expect(TemporaryFilePolicy.isTemporaryFile(versioned))
    #expect(!TemporaryFilePolicy.isHideableTemporaryFile(versioned))
    #expect(!TemporaryFilePolicy.isTemporaryFile(
        directory
    ))
    #expect(!TemporaryFilePolicy.isHideableTemporaryFile(directory))
    #expect(TemporaryFilePolicy.isTemporaryFile(unknownKind))
    #expect(!TemporaryFilePolicy.isHideableTemporaryFile(unknownKind))
}

@Test func repositoryCleanupUsesOnlyStrongTemporaryFileNames() {
    let strongPaths = [
        ".DS_Store",
        "자료/._원본.pdf",
        "문서/~$보고서.DOCX",
        "Icon\r",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".apdisk",
    ]
    let weakPaths = [
        "메모.txt~",
        ".main.swift.swp",
        ".main.swift.swo",
        "#메모.txt#",
        ".#메모.txt",
        "~$그림.png",
    ]

    for path in strongPaths {
        #expect(TemporaryFilePolicy.isRepositoryCleanupCandidate(
            SVNStatusEntry(path: path, item: .added)
        ), "강한 정리 후보가 누락됨: \(path)")
    }
    for path in weakPaths {
        #expect(!TemporaryFilePolicy.isRepositoryCleanupCandidate(
            SVNStatusEntry(path: path, item: .added)
        ), "약한 이름이 정리 후보로 포함됨: \(path)")
    }
}

@Test func repositoryCleanupValidatesMagicBytesAndOfficeLockSize() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("repository-cleanup-validation-\(UUID().uuidString)", isDirectory: true)
    let validDirectory = root.appendingPathComponent("valid", isDirectory: true)
    let fakeDirectory = root.appendingPathComponent("fake", isDirectory: true)
    try FileManager.default.createDirectory(at: validDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fakeDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31, 0x00])
        .write(to: validDirectory.appendingPathComponent(".DS_Store"))
    try Data("not a DS Store".utf8)
        .write(to: fakeDirectory.appendingPathComponent(".DS_Store"))
    try Data([0x00, 0x05, 0x16, 0x07, 0x00])
        .write(to: root.appendingPathComponent("._원본.pdf"))
    try Data(repeating: 0x41, count: TemporaryFilePolicy.maximumOfficeLockFileSize + 1)
        .write(to: root.appendingPathComponent("~$보고서.xlsx"))
    try Data("owner".utf8)
        .write(to: root.appendingPathComponent("~$작은파일.xlsx"))

    let assessments = TemporaryFilePolicy.validateRepositoryCleanupCandidates(
        paths: [
            "valid/.DS_Store",
            "fake/.DS_Store",
            "._원본.pdf",
            "~$보고서.xlsx",
            "~$작은파일.xlsx",
        ],
        in: root
    )
    let byPath = Dictionary(uniqueKeysWithValues: assessments.map { ($0.path, $0) })

    #expect(byPath["valid/.DS_Store"]?.isEligible == true)
    #expect(byPath["._원본.pdf"]?.isEligible == true)
    #expect(byPath["~$작은파일.xlsx"]?.isEligible == true)
    #expect(byPath["fake/.DS_Store"]?.failure == .invalidDSStoreSignature)
    #expect(
        byPath["~$보고서.xlsx"]?.failure
            == .officeLockFileTooLarge(maximumBytes: TemporaryFilePolicy.maximumOfficeLockFileSize)
    )
    #expect(Set(assessments.lazy.filter(\.isEligible).map(\.path)) == [
        "valid/.DS_Store",
        "._원본.pdf",
        "~$작은파일.xlsx",
    ])
}

@MainActor
@Test func updateCleanupReviewExcludesValidationFailuresAndDefaultsToOff() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("repository-cleanup-update-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])
        .write(to: root.appendingPathComponent(".DS_Store"))
    try Data("fake".utf8).write(to: root.appendingPathComponent("._fake"))

    let project = SVNProject(name: "프로젝트", path: root.path)
    let changes = [
        SVNStatusEntry(path: ".DS_Store", item: .added),
        SVNStatusEntry(path: "._fake", item: .added),
    ]
    let client = StubSVNClient(remoteChangesByPath: [project.path: changes])
    let store = makeStore(projects: [project], client: client)

    await store.previewUpdate()
    #expect(store.shouldOfferRepositoryTemporaryFileCleanup)
    #expect(!store.cleansRepositoryTemporaryFilesAfterUpdate)

    store.cleansRepositoryTemporaryFilesAfterUpdate = true
    await store.update()

    #expect(store.isShowingTemporaryFileCleanup)
    #expect(store.selectedTemporaryFileCleanupPaths == [".DS_Store"])
    #expect(
        store.temporaryFileCleanupAssessments.first { $0.path == "._fake" }?.failure
            == .invalidAppleDoubleSignature
    )

    await store.confirmRepositoryTemporaryFileCleanup()
    #expect(await client.requestedRepositoryCleanupDeletionPaths() == [".DS_Store"])
    let commit = await client.lastCommitRequest()
    #expect(commit?.paths == [".DS_Store"])
    #expect(commit?.message == "Mac/Office 임시파일 정리\n\n- .DS_Store")
}

@MainActor
@Test func updatePreviewDoesNotOfferCleanupWithoutStrongCandidates() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/no-cleanup-candidates")
    let client = StubSVNClient(remoteChangesByPath: [project.path: [
        SVNStatusEntry(path: "메모.txt~", item: .added),
        SVNStatusEntry(path: ".DS_Store", item: .deleted),
    ]])
    let store = makeStore(projects: [project], client: client)

    await store.previewUpdate()

    #expect(!store.shouldOfferRepositoryTemporaryFileCleanup)
    #expect(!store.cleansRepositoryTemporaryFilesAfterUpdate)
}

@MainActor
@Test func hiddenTemporaryFilesAreAbsentAndCannotBeCommitted() async {
    let store = makeStore(
        projects: [SVNProject(name: "프로젝트", path: "/tmp/project")],
        hideTemporaryFiles: true
    )
    let modified = SVNStatusEntry(path: "보고서.xlsx", item: .modified, nodeKind: .file)
    let unversioned = SVNStatusEntry(path: "새 문서.xlsx", item: .unversioned, nodeKind: .file)
    let temporary = SVNStatusEntry(path: "~$보고서.xlsx", item: .unversioned, nodeKind: .file)
    store.statuses = [modified, unversioned, temporary]

    #expect(store.visibleStatuses == [modified, unversioned])
    #expect(store.selectableStatusPaths == [modified.path, unversioned.path])
    #expect(store.selectAllStatusPaths == [modified.path, unversioned.path])

    store.selectedPaths.insert(temporary.path)
    #expect(!store.canCommitSelectedPaths)
    #expect(!(await store.commit(message: "임시파일 제외")))
}

@MainActor
@Test func hiddenModeKeepsVersionedTemporaryFilesVisibleAndCommittable() async {
    let store = makeStore(
        projects: [SVNProject(name: "프로젝트", path: "/tmp/project")],
        hideTemporaryFiles: true
    )
    let versionedTemporary = SVNStatusEntry(
        path: "~$기존문서.xlsx",
        item: .modified,
        nodeKind: .file
    )
    let unknownKindTemporary = SVNStatusEntry(path: "~$종류미상", item: .unversioned)
    store.statuses = [versionedTemporary, unknownKindTemporary]

    #expect(store.visibleStatuses == [versionedTemporary, unknownKindTemporary])
    #expect(store.selectableStatusPaths == [versionedTemporary.path, unknownKindTemporary.path])
    #expect(store.selectAllStatusPaths == [versionedTemporary.path, unknownKindTemporary.path])

    store.selectedPaths = [versionedTemporary.path]
    #expect(store.canCommitSelectedPaths)
    #expect(await store.commit(message: "버전관리 임시파일 수정"))
}

@MainActor
@Test func shownTemporaryFilesRemainManualCommitCandidatesButNotSelectAllCandidates() {
    let store = makeStore(
        projects: [SVNProject(name: "프로젝트", path: "/tmp/project")],
        hideTemporaryFiles: false
    )
    let modified = SVNStatusEntry(path: "보고서.xlsx", item: .modified, nodeKind: .file)
    let temporary = SVNStatusEntry(path: "~$보고서.xlsx", item: .unversioned, nodeKind: .file)
    store.statuses = [modified, temporary]

    #expect(store.visibleStatuses == [modified, temporary])
    #expect(store.selectableStatusPaths == [modified.path, temporary.path])
    #expect(store.selectAllStatusPaths == [modified.path])

    store.selectedPaths = [temporary.path]
    #expect(store.canCommitSelectedPaths)
}

@MainActor
@Test func comparesGitIgnoreAndAppliesOnlySelectedSVNPropertyProposals() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-gitignore-store-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("/build/\n!keep.txt\n".utf8)
        .write(to: directory.appendingPathComponent(".gitignore"))

    let project = SVNProject(name: "프로젝트", path: directory.path)
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client)

    await store.compareGitIgnore()

    #expect(store.gitIgnoreFileExists)
    #expect(store.gitIgnoreImportItems.count == 2)
    #expect(store.selectedGitIgnoreImportIDs == [".#1"])

    await store.applySelectedGitIgnoreRules()

    #expect(await client.requestedAddedIgnoreRules() == [
        SVNIgnoreRule(directory: ".", pattern: "build", propertyKind: .local),
    ])
    #expect(try String(contentsOf: directory.appendingPathComponent(".gitignore"), encoding: .utf8) == "/build/\n!keep.txt\n")
}

@MainActor
@Test func comparesGitIgnoreAcrossNestedDirectories() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-gitignore-nested-store-test-\(UUID().uuidString)", isDirectory: true)
    let libDirectory = directory.appendingPathComponent("lib", isDirectory: true)
    try FileManager.default.createDirectory(at: libDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("*.log\n".utf8).write(to: directory.appendingPathComponent(".gitignore"))
    try Data("build/\n".utf8).write(to: libDirectory.appendingPathComponent(".gitignore"))

    let project = SVNProject(name: "프로젝트", path: directory.path)
    let client = StubSVNClient(workingCopyEntries: [
        SVNWorkingCopyEntry(path: "lib", status: "normal", revision: "5"),
    ])
    let store = makeStore(projects: [project], client: client)

    await store.compareGitIgnore()

    #expect(store.gitIgnoreFileExists)
    #expect(store.gitIgnoreImportItems.count == 2)
    #expect(Set(store.gitIgnoreImportItems.map(\.rule.sourceDirectory)) == [".", "lib"])

    let nestedItem = try #require(store.gitIgnoreImportItems.first { $0.rule.sourceDirectory == "lib" })
    #expect(nestedItem.proposal == SVNIgnoreRule(directory: "lib", pattern: "build", propertyKind: .global))
}

@MainActor
@Test func deletionRequestWaitsForConfirmationAndSelectsOnlyVerifiedDeletedPaths() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/delete-flow")
    let missing = SVNStatusEntry(path: "old.txt", item: .missing, revision: "10", nodeKind: .file)
    let before = SVNWorkingCopySnapshot(
        statuses: [missing],
        revision: SVNWorkingCopyRevision(minimum: "10", maximum: "10"),
        collisions: [],
        versionedPathsByCanonicalKey: ["old.txt": ["old.txt"]]
    )
    let after = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: "old.txt", item: .deleted, revision: "10", nodeKind: .file)],
        revision: before.revision,
        collisions: [],
        versionedPathsByCanonicalKey: ["old.txt": ["old.txt"]]
    )
    let client = StubSVNClient(
        snapshotsByPath: [project.path: before],
        postDeletionSnapshotsByPath: [project.path: after]
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = [missing]

    store.requestDeletion(missing)

    let request = try #require(store.deletionRequest)
    #expect(await client.scheduleDeletionRequestCount() == 0)

    await store.confirmDeletion(request)

    #expect(await client.scheduleDeletionRequestCount() == 1)
    #expect(store.statuses.first?.item == .deleted)
    #expect(store.selectedPaths == ["old.txt"])
}

@MainActor
@Test func deletionConfirmationIsDiscardedAfterProjectSwitch() async throws {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/delete-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/delete-second")
    let missing = SVNStatusEntry(path: "old.txt", item: .missing, revision: "10")
    let client = StubSVNClient()
    let store = makeStore(projects: [first, second], client: client)
    store.statuses = [missing]
    store.requestDeletion(missing)
    let request = try #require(store.deletionRequest)

    store.selectedProjectID = second.id
    await store.confirmDeletion(request)

    #expect(await client.scheduleDeletionRequestCount() == 0)
    #expect(store.selectedPaths.isEmpty)
}

@MainActor
@Test func restoredProjectsExposeOnlyConfirmedFilenameNormalizationWarnings() async {
    let warningProject = SVNProject(name: "HFS 프로젝트", path: "/Volumes/HFS/project")
    let unknownProject = SVNProject(name: "알 수 없는 프로젝트", path: "/Volumes/Unknown/project")
    let gate = AsyncTestGate()
    let probe = StubVolumeNormalizationProbe(results: [
        warningProject.path: false,
        unknownProject.path: nil,
    ], gate: gate)

    let store = makeStore(
        projects: [warningProject, unknownProject],
        volumeNormalizationProbe: probe
    )
    #expect(store.filenameNormalizationWarningProjectIDs.isEmpty)

    await gate.release()
    await store.waitForFilenameNormalizationProbes()

    #expect(store.filenameNormalizationWarningProjectIDs == [warningProject.id])
    #expect(Set(await probe.probedPaths) == [warningProject.path, unknownProject.path])
}

@MainActor
private func makeStore(
    projects: [SVNProject],
    client: StubSVNClient = StubSVNClient(),
    fileService: any WorkingCopyFileListing = WorkingCopyFileService(),
    conflictFileService: ConflictFileService = ConflictFileService(),
    workspaceOpener: any WorkspaceOpening = StubWorkspaceOpener(),
    projectPathChecker: any ProjectPathChecking = StubProjectPathChecker(),
    volumeNormalizationProbe: any VolumeNormalizationProbing = StubVolumeNormalizationProbe(),
    hideTemporaryFiles: Bool = true
) -> ProjectStore {
    ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(projects: projects),
        projectAccessManager: StubProjectAccessManager(),
        conflictFileService: conflictFileService,
        workingCopyFileService: fileService,
        workspaceOpener: workspaceOpener,
        projectPathChecker: projectPathChecker,
        volumeNormalizationProbe: volumeNormalizationProbe,
        hideTemporaryFiles: hideTemporaryFiles
    )
}

private func makeLog(revision: String) -> SVNLogEntry {
    SVNLogEntry(revision: revision, author: "tester", date: nil, message: "test")
}

private func makePathCollision(path: String, repairable: Bool) -> SVNPathCollision {
    SVNPathCollision(
        canonicalPath: path,
        rawPaths: [path, path.decomposedStringWithCanonicalMapping],
        affectedEntryCount: 2,
        repairableRawPath: repairable ? path.decomposedStringWithCanonicalMapping : nil
    )
}

private func makeRepositoryPathNormalizationTarget(
    _ path: String,
    isDirectory: Bool = false
) -> SVNRepositoryPathNormalizationTarget {
    SVNRepositoryPathNormalizationTarget(
        repositoryPath: path.decomposedStringWithCanonicalMapping,
        normalizedPath: path.precomposedStringWithCanonicalMapping,
        isDirectory: isDirectory
    )
}

private enum TestError: Error {
    case credentialWriteFailed
    case backupFailed
    case resolveConflictFailed
    case lockInfoFailed
    case automaticRefreshFailed
    case staleRepositoryLocksFailed
    case repositoryPathNormalizationScanFailed
}

private actor StubVolumeNormalizationProbe: VolumeNormalizationProbing {
    private let results: [String: Bool?]
    private let gate: AsyncTestGate?
    private(set) var probedPaths: [String] = []

    init(results: [String: Bool?] = [:], gate: AsyncTestGate? = nil) {
        self.results = results
        self.gate = gate
    }

    func preservesPrecomposedFilenames(at directoryPath: String) async -> Bool? {
        await gate?.wait()
        probedPaths.append(directoryPath)
        return results[directoryPath] ?? nil
    }
}

private actor AsyncTestGate {
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private func waitForConflictDetailsRequest(_ client: StubSVNClient, path: String) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if await client.conflictDetailsRequestCount(for: path) > 0 { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("충돌 상세 요청이 시작되지 않았습니다: \(path)")
}

private func waitUntilCheckoutStarts(_ client: StubSVNClient) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if await client.hasStartedCheckout() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("체크아웃이 시작되지 않았습니다.")
}

private func waitForResolveRequest(_ client: StubSVNClient) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if await client.conflictChoiceCount() > 0 { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("충돌 해결 요청이 시작되지 않았습니다.")
}

private func workingRecoveryURLs(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter {
        $0.lastPathComponent.hasPrefix(".working-file-recovery")
            && !$0.lastPathComponent.hasSuffix(".staging")
    }
}

private final class ProjectStoreConflictFixture {
    let root: URL
    let project: SVNProject
    let backupRoot: URL
    let details: SVNConflictDetails
    let workingFileURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: workingCopy, withIntermediateDirectories: true)

        let mine = workingCopy.appendingPathComponent("conflicts/document.mine")
        let server = workingCopy.appendingPathComponent("conflicts/document.server")
        try FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: mine)
        try Data("server".utf8).write(to: server)

        project = SVNProject(name: "충돌 프로젝트", path: workingCopy.path)
        workingFileURL = workingCopy.appendingPathComponent("Documents/document.txt")
        try FileManager.default.createDirectory(
            at: workingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("working conflict markers".utf8).write(to: workingFileURL)
        details = SVNConflictDetails(
            path: "Documents/document.txt",
            type: "text",
            operation: "update",
            myFile: "conflicts/document.mine",
            serverFile: "conflicts/document.server",
            serverRevision: "42"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func details(replacingTypeWith type: String) -> SVNConflictDetails {
        SVNConflictDetails(
            path: details.path,
            type: type,
            operation: details.operation,
            myFile: details.myFile,
            serverFile: details.serverFile,
            serverRevision: details.serverRevision
        )
    }

    func makeAdditionalConflict(path: String, stem: String) throws -> SVNConflictDetails {
        let conflicts = URL(fileURLWithPath: project.path, isDirectory: true)
            .appendingPathComponent("conflicts", isDirectory: true)
        let mine = conflicts.appendingPathComponent("\(stem).mine")
        let server = conflicts.appendingPathComponent("\(stem).server")
        try Data("\(stem)-mine".utf8).write(to: mine)
        try Data("\(stem)-server".utf8).write(to: server)
        let working = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: working.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(stem)-working".utf8).write(to: working)
        return SVNConflictDetails(
            path: path,
            type: "text",
            operation: "update",
            myFile: "conflicts/\(stem).mine",
            serverFile: "conflicts/\(stem).server",
            serverRevision: "43"
        )
    }
}

private struct RevertCall: Equatable, Sendable {
    let workingCopyPath: String
    let relativePath: String
}

private struct RemoteRefreshRequestCounts: Equatable, Sendable {
    let log: Int
    let outOfDate: Int
}

private struct RevisionDiffRequest: Equatable, Sendable {
    let revision: String
    let repositoryPath: String
    let workingCopyRepositoryPath: String?
    let pegRevision: String
}

private struct CommitRequest: Equatable, Sendable {
    let paths: [String]
    let message: String
}

private actor StubSVNClient: SVNClientServing {
    let statusesByPath: [String: [SVNStatusEntry]]
    let revisionsByPath: [String: String]
    let delaysByPath: [String: Duration]
    let remoteChangesByPath: [String: [SVNStatusEntry]]
    let fileLogsByPath: [String: [SVNLogEntry]]
    let checkoutResult: String
    let checkoutProgress: [String]
    let checkoutRunsUntilCancelled: Bool
    let validateWorkingCopyError: Error?
    let verifyCredentialsError: Error?
    private var checkoutStarted = false
    private var validatedPaths: [String] = []
    private var verifiedCredentials: [SVNCredentials?] = []
    let lockInfoByPath: [String: SVNLockInfo]
    let lockInfoError: Error?
    let snapshotError: Error?
    let workingCopyEntriesError: Error?
    let repositoryLocksByPath: [String: [SVNLockInfo]]
    let repositoryLocksErrorsByPath: [String: Error]
    let snapshotsByPath: [String: SVNWorkingCopySnapshot]
    let postResolveSnapshotsByPath: [String: SVNWorkingCopySnapshot]
    let repairedSnapshotsByPath: [String: SVNWorkingCopySnapshot]
    let postDeletionSnapshotsByPath: [String: SVNWorkingCopySnapshot]
    let recoveryPreviewValue: SVNRecoveryPreview
    let recoveryResultValue: SVNRecoveryResult
    let commitCompletedWarning: (output: String, details: String)?
    let conflictDetailsValue: SVNConflictDetails?
    let conflictDetailsByRelativePath: [String: SVNConflictDetails]
    let conflictDetailsGatesByRelativePath: [String: AsyncTestGate]
    let resolveError: Error?
    let resolveGate: AsyncTestGate?
    let workingCopyEntriesValue: [SVNWorkingCopyEntry]
    let ignoreRulesValue: [SVNIgnoreRule]
    let commitError: SVNError?
    let repositoryPathNormalizationTargetsValue: [SVNRepositoryPathNormalizationTarget]
    let repositoryPathNormalizationResultValue: SVNRepositoryPathNormalizationResult?
    let repositoryPathNormalizationError: SVNRepositoryPathNormalizationError?
    let repositoryPathNormalizationScanError: Error?
    let repositoryPathNormalizationScanGate: AsyncTestGate?
    private var revisionDiffRequests: [RevisionDiffRequest] = []
    private var lockInfoRequests = 0
    private var lockInfoPaths: [String] = []
    private var lockPaths: [String] = []
    private var recoveryPaths: [String] = []
    private var canonicalAliasRepairRequests = 0
    private var snapshotRequests = 0
    private var workingCopyEntriesRequests = 0
    private var repositoryLocksRequests = 0
    private var logRequests = 0
    private var outOfDateRequests = 0
    private var conflictChoices: [SVNConflictChoice] = []
    private var conflictDetailsRequestCounts: [String: Int] = [:]
    private var revertCalls: [RevertCall] = []
    private var conflictDetailsRequestRawPaths: [Data] = []
    private var resolvedPaths: [String] = []
    private var addedIgnoreRules: [SVNIgnoreRule] = []
    private var scheduleDeletionRequests = 0
    private var repositoryPathNormalizationScanRequests = 0
    private var repositoryPathNormalizationRequests = 0
    private var updateRequests = 0
    private var repositoryCleanupDeletionPaths: [String] = []
    private var commitRequests: [CommitRequest] = []

    init(
        statusesByPath: [String: [SVNStatusEntry]] = [:],
        revisionsByPath: [String: String] = [:],
        delaysByPath: [String: Duration] = [:],
        remoteChangesByPath: [String: [SVNStatusEntry]] = [:],
        fileLogsByPath: [String: [SVNLogEntry]] = [:],
        checkoutResult: String = "checked out",
        checkoutProgress: [String] = [],
        checkoutRunsUntilCancelled: Bool = false,
        validateWorkingCopyError: Error? = nil,
        verifyCredentialsError: Error? = nil,
        lockInfoByPath: [String: SVNLockInfo] = [:],
        lockInfoError: Error? = nil,
        snapshotError: Error? = nil,
        workingCopyEntriesError: Error? = nil,
        repositoryLocksByPath: [String: [SVNLockInfo]] = [:],
        repositoryLocksErrorsByPath: [String: Error] = [:],
        snapshotsByPath: [String: SVNWorkingCopySnapshot] = [:],
        postResolveSnapshotsByPath: [String: SVNWorkingCopySnapshot] = [:],
        repairedSnapshotsByPath: [String: SVNWorkingCopySnapshot] = [:],
        postDeletionSnapshotsByPath: [String: SVNWorkingCopySnapshot] = [:],
        recoveryPreview: SVNRecoveryPreview = SVNRecoveryPreview(
            mappings: [], ignoredAliasCount: 0, blockingPaths: []
        ),
        recoveryResult: SVNRecoveryResult? = nil,
        commitCompletedWarning: (output: String, details: String)? = nil,
        conflictDetailsValue: SVNConflictDetails? = nil,
        conflictDetailsByRelativePath: [String: SVNConflictDetails] = [:],
        conflictDetailsGatesByRelativePath: [String: AsyncTestGate] = [:],
        resolveError: Error? = nil,
        resolveGate: AsyncTestGate? = nil,
        workingCopyEntries: [SVNWorkingCopyEntry] = [],
        ignoreRules: [SVNIgnoreRule] = [],
        commitError: SVNError? = nil,
        repositoryPathNormalizationTargets: [SVNRepositoryPathNormalizationTarget] = [],
        repositoryPathNormalizationResult: SVNRepositoryPathNormalizationResult? = nil,
        repositoryPathNormalizationError: SVNRepositoryPathNormalizationError? = nil,
        repositoryPathNormalizationScanError: Error? = nil,
        repositoryPathNormalizationScanGate: AsyncTestGate? = nil
    ) {
        self.statusesByPath = statusesByPath
        self.revisionsByPath = revisionsByPath
        self.delaysByPath = delaysByPath
        self.remoteChangesByPath = remoteChangesByPath
        self.fileLogsByPath = fileLogsByPath
        self.checkoutResult = checkoutResult
        self.checkoutProgress = checkoutProgress
        self.checkoutRunsUntilCancelled = checkoutRunsUntilCancelled
        self.validateWorkingCopyError = validateWorkingCopyError
        self.verifyCredentialsError = verifyCredentialsError
        self.lockInfoByPath = lockInfoByPath
        self.lockInfoError = lockInfoError
        self.snapshotError = snapshotError
        self.workingCopyEntriesError = workingCopyEntriesError
        self.repositoryLocksByPath = repositoryLocksByPath
        self.repositoryLocksErrorsByPath = repositoryLocksErrorsByPath
        self.snapshotsByPath = snapshotsByPath
        self.postResolveSnapshotsByPath = postResolveSnapshotsByPath
        self.repairedSnapshotsByPath = repairedSnapshotsByPath
        self.postDeletionSnapshotsByPath = postDeletionSnapshotsByPath
        self.commitCompletedWarning = commitCompletedWarning
        self.conflictDetailsValue = conflictDetailsValue
        self.conflictDetailsByRelativePath = conflictDetailsByRelativePath
        self.conflictDetailsGatesByRelativePath = conflictDetailsGatesByRelativePath
        self.resolveError = resolveError
        self.resolveGate = resolveGate
        self.commitError = commitError
        repositoryPathNormalizationTargetsValue = repositoryPathNormalizationTargets
        repositoryPathNormalizationResultValue = repositoryPathNormalizationResult
        self.repositoryPathNormalizationError = repositoryPathNormalizationError
        self.repositoryPathNormalizationScanError = repositoryPathNormalizationScanError
        self.repositoryPathNormalizationScanGate = repositoryPathNormalizationScanGate
        workingCopyEntriesValue = workingCopyEntries
        ignoreRulesValue = ignoreRules
        recoveryPreviewValue = recoveryPreview
        recoveryResultValue = recoveryResult ?? SVNRecoveryResult(
            destinationPath: "/tmp/recovered",
            snapshot: SVNWorkingCopySnapshot(
                statuses: [],
                revision: SVNWorkingCopyRevision(minimum: "0", maximum: "0"),
                collisions: [],
                versionedPathsByCanonicalKey: [:]
            ),
            migratedPaths: []
        )
    }

    private func delay(for path: String) async {
        if let duration = delaysByPath[path] { try? await Task.sleep(for: duration) }
    }

    func checkout(repositoryURL: String, destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String { checkoutResult }
    func checkout(repositoryURL: String, destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, progress: SVNOutputHandler?) async throws -> String {
        for output in checkoutProgress { progress?(output) }
        if checkoutRunsUntilCancelled {
            checkoutStarted = true
            // 실제 SVNClient는 취소 시 svn 프로세스를 종료하고 CancellationError를
            // 던집니다. sleep도 같은 오류를 던지므로 취소 경로를 그대로 재현합니다.
            try await Task.sleep(for: .seconds(60))
        }
        return checkoutResult
    }
    func validateWorkingCopy(at path: String, credentials: SVNCredentials?) async throws {
        validatedPaths.append(path)
        if let validateWorkingCopyError { throw validateWorkingCopyError }
    }

    func verifyCredentials(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws {
        verifiedCredentials.append(credentials)
        if let verifyCredentialsError { throw verifyCredentialsError }
    }

    func recordedVerifiedCredentials() -> [SVNCredentials?] { verifiedCredentials }
    func recordedValidatedPaths() -> [String] { validatedPaths }
    func hasStartedCheckout() -> Bool { checkoutStarted }
    func status(at path: String, credentials: SVNCredentials?) async throws -> [SVNStatusEntry] {
        await delay(for: path)
        return statusesByPath[path] ?? []
    }
    func workingCopyEntries(at path: String, credentials: SVNCredentials?) async throws -> [SVNWorkingCopyEntry] {
        workingCopyEntriesRequests += 1
        await delay(for: path)
        if let workingCopyEntriesError { throw workingCopyEntriesError }
        return workingCopyEntriesValue
    }
    func workingCopySnapshot(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopySnapshot {
        snapshotRequests += 1
        await delay(for: path)
        if let snapshotError { throw snapshotError }
        if !conflictChoices.isEmpty, let snapshot = postResolveSnapshotsByPath[path] { return snapshot }
        if scheduleDeletionRequests > 0, let snapshot = postDeletionSnapshotsByPath[path] { return snapshot }
        if canonicalAliasRepairRequests > 0, let snapshot = repairedSnapshotsByPath[path] { return snapshot }
        if let snapshot = snapshotsByPath[path] { return snapshot }
        let revision = revisionsByPath[path] ?? "0"
        return SVNWorkingCopySnapshot(
            statuses: statusesByPath[path] ?? [],
            revision: SVNWorkingCopyRevision(minimum: revision, maximum: revision),
            collisions: [],
            versionedPathsByCanonicalKey: [:]
        )
    }
    func snapshotRequestCount() -> Int { snapshotRequests }
    func workingCopyEntriesRequestCount() -> Int { workingCopyEntriesRequests }
    func repositoryLocksRequestCount() -> Int { repositoryLocksRequests }
    func remoteRefreshRequestCounts() -> RemoteRefreshRequestCounts {
        RemoteRefreshRequestCounts(log: logRequests, outOfDate: outOfDateRequests)
    }
    func repairCanonicalAliases(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopySnapshot {
        canonicalAliasRepairRequests += 1
        if let repairedSnapshot = repairedSnapshotsByPath[path] { return repairedSnapshot }
        return try await workingCopySnapshot(at: path, credentials: credentials)
    }
    func repairRequestCount() -> Int { canonicalAliasRepairRequests }
    func recoveryPreview(at path: String, credentials: SVNCredentials?) async throws -> SVNRecoveryPreview {
        recoveryPreviewValue
    }
    func recoverWorkingCopy(from sourcePath: String, to destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> SVNRecoveryResult {
        recoveryPaths = [sourcePath, destinationPath]
        return recoveryResultValue
    }
    func repositoryPathsNeedingNormalization(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNRepositoryPathNormalizationTarget] {
        repositoryPathNormalizationScanRequests += 1
        await repositoryPathNormalizationScanGate?.wait()
        if let repositoryPathNormalizationScanError { throw repositoryPathNormalizationScanError }
        return repositoryPathNormalizationTargetsValue
    }
    func normalizeRepositoryPaths(_ targets: [SVNRepositoryPathNormalizationTarget], at path: String, message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> SVNRepositoryPathNormalizationResult {
        repositoryPathNormalizationRequests += 1
        if let repositoryPathNormalizationError { throw repositoryPathNormalizationError }
        return repositoryPathNormalizationResultValue ?? SVNRepositoryPathNormalizationResult(
            renamedTargets: targets,
            skippedTargets: [],
            committedRevisions: []
        )
    }
    func repositoryPathNormalizationScanRequestCount() -> Int { repositoryPathNormalizationScanRequests }
    func repositoryPathNormalizationRequestCount() -> Int { repositoryPathNormalizationRequests }
    func lastRecoveryPaths() -> [String] { recoveryPaths }
    func ignoredStatus(at path: String, credentials: SVNCredentials?) async throws -> [SVNStatusEntry] { [] }
    func ignoreRules(at path: String, credentials: SVNCredentials?) async throws -> [SVNIgnoreRule] { ignoreRulesValue }
    func addIgnoreRule(at path: String, directory: String, pattern: String, propertyKind: SVNIgnorePropertyKind, credentials: SVNCredentials?) async throws {
        addedIgnoreRules.append(SVNIgnoreRule(directory: directory, pattern: pattern, propertyKind: propertyKind))
    }
    func requestedAddedIgnoreRules() -> [SVNIgnoreRule] { addedIgnoreRules }
    func removeIgnoreRule(at path: String, directory: String, pattern: String, propertyKind: SVNIgnorePropertyKind, credentials: SVNCredentials?) async throws {}
    func scheduleDeletion(at path: String, paths: [String], credentials: SVNCredentials?) async throws -> SVNDeletionResult {
        scheduleDeletionRequests += 1
        return SVNDeletionResult(scheduledPaths: paths, failedPaths: [])
    }
    func scheduleDeletionRequestCount() -> Int { scheduleDeletionRequests }
    func scheduleRepositoryCleanupDeletion(at path: String, relativePath: String, credentials: SVNCredentials?) async throws {
        repositoryCleanupDeletionPaths.append(relativePath)
    }
    func requestedRepositoryCleanupDeletionPaths() -> [String] { repositoryCleanupDeletionPaths }
    func repositoryLocks(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLockInfo] {
        repositoryLocksRequests += 1
        await delay(for: path)
        if let error = repositoryLocksErrorsByPath[path] { throw error }
        return repositoryLocksByPath[path] ?? []
    }
    func lockInfo(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> SVNLockInfo? {
        lockInfoRequests += 1
        lockInfoPaths.append(relativePath)
        if let lockInfoError { throw lockInfoError }
        return lockInfoByPath[relativePath]
    }
    func lockInfoRequestCount() -> Int { lockInfoRequests }
    func requestedLockInfoPaths() -> [String] { lockInfoPaths }
    func lock(at path: String, relativePath: String, comment: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String {
        lockPaths.append(relativePath)
        return "locked"
    }
    func requestedLockPaths() -> [String] { lockPaths }
    func unlock(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String { "unlocked" }
    func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> SVNConflictDetails? {
        conflictDetailsRequestCounts[relativePath, default: 0] += 1
        conflictDetailsRequestRawPaths.append(Data(relativePath.utf8))
        if let gate = conflictDetailsGatesByRelativePath[relativePath] { await gate.wait() }
        await delay(for: path)
        return conflictDetailsByRelativePath[relativePath] ?? conflictDetailsValue
    }
    func resolveConflict(at path: String, relativePath: String, choice: SVNConflictChoice, credentials: SVNCredentials?) async throws -> String {
        conflictChoices.append(choice)
        resolvedPaths.append(relativePath)
        if let resolveGate { await resolveGate.wait() }
        if let resolveError { throw resolveError }
        return "resolved"
    }
    func lastConflictChoice() -> SVNConflictChoice? { conflictChoices.last }
    func lastResolvedPath() -> String? { resolvedPaths.last }
    func conflictChoiceCount() -> Int { conflictChoices.count }
    func conflictDetailsRequestCount(for path: String) -> Int { conflictDetailsRequestCounts[path, default: 0] }
    func exactConflictDetailsRequestCount(for path: String) -> Int {
        conflictDetailsRequestRawPaths.filter { $0 == Data(path.utf8) }.count
    }
    func log(at path: String, limit: Int, endingAtRevision: String?, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLogEntry] {
        logRequests += 1
        await delay(for: path)
        return [makeLog(revision: revisionsByPath[path] ?? "0")]
    }
    func revisionDiff(at path: String, revision: String, repositoryPath: String, workingCopyRepositoryPath: String?, pegRevision: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String {
        revisionDiffRequests.append(RevisionDiffRequest(
            revision: revision,
            repositoryPath: repositoryPath,
            workingCopyRepositoryPath: workingCopyRepositoryPath,
            pegRevision: pegRevision
        ))
        return "revision diff"
    }
    func lastRevisionDiffRequest() -> RevisionDiffRequest? { revisionDiffRequests.last }
    func workingCopyRevision(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopyRevision {
        await delay(for: path)
        let revision = revisionsByPath[path] ?? "0"
        return SVNWorkingCopyRevision(minimum: revision, maximum: revision)
    }
    func workingCopyRepositoryPath(at path: String, credentials: SVNCredentials?) async throws -> String { "/trunk" }
    func workingCopyIsOutOfDate(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> Bool {
        outOfDateRequests += 1
        await delay(for: path)
        return false
    }
    func remoteChanges(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNStatusEntry] {
        await delay(for: path)
        return remoteChangesByPath[path] ?? []
    }
    func update(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String {
        updateRequests += 1
        return "updated"
    }
    func updateRequestCount() -> Int { updateRequests }
    func diff(at path: String, relativePath: String?, credentials: SVNCredentials?) async throws -> String { "diff" }
    func revert(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> String {
        await delay(for: path)
        revertCalls.append(RevertCall(workingCopyPath: path, relativePath: relativePath))
        return "reverted"
    }
    func requestedReverts() -> [RevertCall] { revertCalls }
    func fileLog(at path: String, relativePath: String, limit: Int, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLogEntry] {
        await delay(for: path)
        return fileLogsByPath[path] ?? []
    }
    func commit(at path: String, paths: [String], message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String {
        commitRequests.append(CommitRequest(paths: paths, message: message))
        if let commitCompletedWarning {
            throw SVNError.commitSucceededWithValidationWarning(
                output: commitCompletedWarning.output,
                details: commitCompletedWarning.details
            )
        }
        if let commitError { throw commitError }
        return "committed"
    }
    func lastCommitRequest() -> CommitRequest? { commitRequests.last }
}

private actor StubWorkingCopyFileService: WorkingCopyFileListing {
    let delaysByPath: [String: Duration]

    init(delaysByPath: [String: Duration]) {
        self.delaysByPath = delaysByPath
    }

    func tree(at rootPath: String, svnEntries: [SVNWorkingCopyEntry]) async throws -> [WorkingCopyFileNode] {
        if let duration = delaysByPath[rootPath] { try? await Task.sleep(for: duration) }
        let name = URL(fileURLWithPath: rootPath).lastPathComponent
        return [WorkingCopyFileNode(
            name: name,
            relativePath: name,
            isDirectory: true,
            isSymbolicLink: false,
            svnEntry: nil,
            children: []
        )]
    }
}

@MainActor
private final class StubWorkspaceOpener: WorkspaceOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

private final class StubCredentialStore: CredentialStoring {
    private var passwords: [UUID: String] = [:]
    private let setError: Error?

    init(setError: Error? = nil) { self.setError = setError }
    func password(for projectID: UUID) throws -> String? { passwords[projectID] }
    func setPassword(_ password: String, for projectID: UUID) throws {
        if let setError { throw setError }
        passwords[projectID] = password
    }
    func deletePassword(for projectID: UUID) throws { passwords[projectID] = nil }
}

private final class MemoryProjectPersistence: ProjectPersisting {
    private let initialProjects: [SVNProject]
    private(set) var savedProjects: [SVNProject] = []

    init(projects: [SVNProject] = []) { initialProjects = projects }
    func loadProjects() -> [SVNProject] { initialProjects }
    func saveProjects(_ projects: [SVNProject]) { savedProjects = projects }
}

private final class StubProjectPathChecker: ProjectPathChecking {
    var directoryExists: Bool

    init(directoryExists: Bool = true) {
        self.directoryExists = directoryExists
    }

    func directoryExists(at path: String) -> Bool {
        directoryExists
    }
}

private final class StubProjectAccessManager: ProjectAccessManaging {
    private(set) var accessedURLs: [SVNProject.ID: URL] = [:]
    private(set) var releasedURLs: [URL] = []

    func makeBookmark(for url: URL) throws -> Data { Data("bookmark".utf8) }
    func restoreAccess(for projects: inout [SVNProject]) {}
    func beginAccessing(_ url: URL, for projectID: SVNProject.ID) {
        accessedURLs[projectID] = url
    }

    func endAccessing(projectID: SVNProject.ID) {
        guard let url = accessedURLs.removeValue(forKey: projectID) else { return }
        releasedURLs.append(url)
    }

    func endAccessing(url: URL) {
        guard let entry = accessedURLs.first(where: { $0.value == url }) else { return }
        endAccessing(projectID: entry.key)
    }
}
