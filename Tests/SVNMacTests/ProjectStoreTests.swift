import Foundation
import SVNCore
import Testing
@testable import SVNMac

@MainActor
@Test func conflictFileErrorsUseRequestedLanguageAtStoreBoundary() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/project")])

    #expect(store.localizedError(ConflictFileError.missingWorkingFile, language: .korean) == "현재 작업 파일을 찾을 수 없습니다.")
    #expect(store.localizedError(ConflictFileError.missingWorkingFile, language: .english) == "The current working file could not be found.")
    #expect(
        store.localizedError(ConflictFileError.unsupportedType("property"), language: .english)
            == "Unsupported conflict type: property\nRevert Local Changes… → Run Update"
    )
    #expect(store.localizedError(SVNError.invalidWorkingCopy, language: .korean) == "선택한 폴더는 SVN 로컬 작업 폴더가 아닙니다.")
    #expect(store.localizedError(SVNError.invalidWorkingCopy, language: .english) == "The selected folder is not an SVN local working folder.")
}

@MainActor
@Test func svnFailureCodesUseActionableGuidanceAndKeepOriginalDetails() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/project")])
    let cleanup = store.localizedError(SVNError.commandFailed(
        command: "svn update",
        message: "svn: E155037: Previous operation has not finished"
    ), language: .korean)
    let conflict = store.localizedError(SVNError.commandFailed(
        command: "svn commit",
        message: "svn: E155015: Aborting commit: '/tmp/project/Docs/report.txt' remains in conflict"
    ), language: .english)
    let unlock = store.localizedError(SVNError.commandFailed(
        command: "svn unlock",
        message: "svn: E195013: 'Docs/report.txt' is not locked in this working copy"
    ), language: .korean)

    #expect(cleanup.contains("정리"))
    #expect(cleanup.contains("E155037"))
    #expect(conflict.contains("/tmp/project/Docs/report.txt"))
    #expect(conflict.contains("Resolve Conflicts"))
    #expect(conflict.contains("E155015"))
    #expect(unlock.contains("강제 해제"))
    #expect(unlock.contains("E195013"))
}

@MainActor
@Test func cleanupFailureOffersCleanupAndOpensProjectSettings() {
    let project = SVNProject(name: "프로젝트", path: "/tmp/cleanup-proposal")
    let store = makeStore(projects: [project])
    let error = SVNError.commandFailed(
        command: "svn update",
        message: "svn: E155004: Working copy locked"
    )

    store.publishRefreshError(error, projectID: project.id, policy: .standalone)

    #expect(store.workingCopyCleanupRequest?.projectID == project.id)
    #expect(store.workingCopyCleanupRequest?.originalMessage.contains("E155004") == true)
    #expect(store.isShowingCredentials)
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func workingCopyCleanupTracksProgressAndRejectsDuplicateRuns() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/cleanup-progress")
    let cleanupGate = AsyncTestGate()
    let client = StubSVNClient(cleanupGate: cleanupGate)
    let store = makeStore(projects: [project], client: client)
    store.requestSelectedWorkingCopyCleanup()

    let firstCleanup = Task { await store.cleanupSelectedWorkingCopy() }
    await cleanupGate.waitUntilEntered()
    let duplicateResult = await store.cleanupSelectedWorkingCopy()

    #expect(store.isCleaningSelectedWorkingCopy)
    #expect(!duplicateResult)
    #expect(await client.cleanupRequestCount() == 1)

    await cleanupGate.release()
    #expect(await firstCleanup.value)
    #expect(!store.isCleaningSelectedWorkingCopy)
    #expect(store.workingCopyCleanupRequest == nil)
}

@MainActor
@Test func cleanupCommandFailureDoesNotOfferAnotherCleanupRetry() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/cleanup-failure")
    let client = StubSVNClient(cleanupError: SVNError.commandFailed(
        command: "svn cleanup",
        message: "svn: E155009: Failed to run the WC DB work queue"
    ))
    let store = makeStore(projects: [project], client: client)
    store.requestSelectedWorkingCopyCleanup()

    let didCleanup = await store.cleanupSelectedWorkingCopy()
    #expect(!didCleanup)
    #expect(store.workingCopyCleanupRequest == nil)
    #expect(store.errorMessage?.contains("E155009") == true)
    #expect(store.errorMessage?.contains("관리자") == true)
}

@MainActor
@Test func failedRegularUnlockOffersForceAndForceCallIsExplicit() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/force-unlock", username: nil)
    let lock = SVNLockInfo(
        path: "Docs/report.txt",
        owner: "former.employee",
        comment: "월말 보고서",
        created: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let client = StubSVNClient(
        unlockErrorWhenNotForced: SVNError.commandFailed(
            command: "svn unlock",
            message: "svn: E195013: 'Docs/report.txt' is not locked in this working copy"
        )
    )
    let store = makeStore(projects: [project], client: client)

    await store.unlock(lock)
    let request = try #require(store.forceUnlockRequest)
    #expect(request.lock == lock)
    #expect(await client.requestedUnlockForces() == [false])

    await store.forceUnlock(request)
    #expect(await client.requestedUnlockForces() == [false, true])
    #expect(store.forceUnlockRequest == nil)
}

@MainActor
@Test func forceUnlockRequestIsConsumedBeforeAwait() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/force-unlock-duplicate")
    let lock = SVNLockInfo(path: "보고서.hwp", owner: "former.employee")
    let gate = AsyncTestGate()
    let client = StubSVNClient(
        unlockErrorWhenNotForced: SVNError.commandFailed(
            command: "svn unlock",
            message: "svn: E195013: not locked in this working copy"
        ),
        forcedUnlockGate: gate
    )
    let store = makeStore(projects: [project], client: client)
    await store.unlock(lock)
    let request = try #require(store.forceUnlockRequest)

    let first = Task { await store.forceUnlock(request) }
    await gate.waitUntilEntered()
    let second = Task { await store.forceUnlock(request) }
    for _ in 0..<100 {
        if await client.requestedUnlockForces().count == 3 { break }
        await Task.yield()
    }
    await gate.release()
    await first.value
    await second.value

    #expect(await client.requestedUnlockForces() == [false, true])
}

@MainActor
@Test func forceLockRequestIsConsumedBeforeAwait() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/force-lock-duplicate")
    let request = ExplicitLockRequest(
        paths: ["보고서.hwp"],
        conflictingLocks: [SVNLockInfo(path: "보고서.hwp", owner: "other-user")]
    )
    let gate = AsyncTestGate()
    let client = StubSVNClient(multiplePathLockGate: gate)
    let store = makeStore(projects: [project], client: client)
    store.recoveryState.explicitLockRequest = request

    let first = Task { await store.forceExplicitLock(request) }
    await gate.waitUntilEntered()
    let second = Task { await store.forceExplicitLock(request) }
    for _ in 0..<100 {
        if await client.multiplePathLockRequestCount() == 2 { break }
        await Task.yield()
    }
    await gate.release()
    await first.value
    await second.value

    #expect(await client.multiplePathLockRequestCount() == 1)
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
    let request = RevertRequest(projectID: project.id, entry: entry)
    store.revertRequest = nil

    await store.confirmRevert(request)

    #expect(await client.requestedReverts() == [
        RevertCall(workingCopyPath: project.path, relativePath: entry.path),
    ])
    #expect(store.statuses.isEmpty)
    #expect(store.selectedPaths.isEmpty)
}

@MainActor
@Test func successfulRevertRefreshesWorkingCopyBrowserCache() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/revert-browser-cache")
    let entry = SVNStatusEntry(path: "보고서.hwp", item: .modified)
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
    let store = makeStore(
        projects: [project],
        client: client,
        fileService: StubWorkingCopyFileService(delaysByPath: [:])
    )
    store.statuses = [entry]
    let generationBeforeRevert = store.workingCopyBrowserRefreshGeneration

    await store.confirmRevert(RevertRequest(projectID: project.id, entry: entry))

    #expect(store.workingCopyBrowserRefreshGeneration == generationBeforeRevert + 1)
    #expect(await client.workingCopyEntriesRequestCount() == 1)
}

@MainActor
@Test func staleRevertCompletionDoesNotMutateNewProject() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/revert-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/revert-second")
    let entry = SVNStatusEntry(path: "보고서.hwp", item: .modified)
    let client = StubSVNClient(delaysByPath: [first.path: .milliseconds(100)])
    let store = makeStore(projects: [first, second], client: client)
    store.selectedPaths = [entry.path]

    let task = Task {
        await store.confirmRevert(RevertRequest(projectID: first.id, entry: entry))
    }
    try? await Task.sleep(for: .milliseconds(10))
    store.selectedProjectID = second.id
    store.notice = "둘째 프로젝트 알림"
    await task.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.notice == "둘째 프로젝트 알림")
}

@MainActor
@Test func staleRevertRequestDoesNotRunAgainstNewProject() async throws {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/revert-request-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/revert-request-second")
    let entry = SVNStatusEntry(path: "보고서.hwp", item: .modified)
    let client = StubSVNClient()
    let store = makeStore(projects: [first, second], client: client)
    store.requestRevert(entry)
    let request = try #require(store.revertRequest)

    store.selectedProjectID = second.id
    await store.confirmRevert(request)

    #expect(await client.requestedReverts().isEmpty)
    #expect(store.revertRequest == nil)
    #expect(store.notice == nil)
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func olderRevertCompletionCannotOverwriteNewerRequestInSameProject() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/revert-request-order")
    let firstEntry = SVNStatusEntry(path: "느린-보고서.hwp", item: .modified)
    let secondEntry = SVNStatusEntry(path: "최신-보고서.hwp", item: .modified)
    let firstGate = AsyncTestGate()
    let client = StubSVNClient(
        revertGatesByRequest: [firstGate],
        revertErrorsByRequest: [nil, TestError.resolveConflictFailed]
    )
    let store = makeStore(projects: [project], client: client)

    let first = Task {
        await store.confirmRevert(RevertRequest(projectID: project.id, entry: firstEntry))
    }
    await firstGate.waitUntilEntered()
    await store.confirmRevert(RevertRequest(projectID: project.id, entry: secondEntry))
    await firstGate.release()
    await first.value

    #expect(store.notice == nil)
    #expect(store.errorMessage == store.localizedError(TestError.resolveConflictFailed))
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
@Test func updateExecutorRejectsDuplicateOperationForSameProject() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/update-duplicate")
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client)
    let existingOperation = store.beginOperation(.update(project.id))

    await store.update()

    store.endOperation(existingOperation)
    #expect(await client.updateRequestCount() == 0)
}

@MainActor
@Test func olderUpdatePreviewCannotOverwriteNewerPreviewForSameProject() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/update-preview-order")
    let firstGate = AsyncTestGate()
    let client = StubSVNClient(
        updatePreviewCommitsByRequest: [
            [makeLog(revision: "1")],
            [makeLog(revision: "2")],
        ],
        updatePreviewGatesByRequest: [firstGate]
    )
    let store = makeStore(projects: [project], client: client)

    let first = Task { await store.previewUpdate() }
    await firstGate.waitUntilEntered()
    await store.previewUpdate()
    await firstGate.release()
    await first.value

    #expect(store.recoveryState.updatePreview.commits.map(\.revision) == ["2"])
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
@Test func olderFileHistoryRequestCannotOverwriteNewerFileInSameProject() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/history-request-order")
    let firstGate = AsyncTestGate()
    let client = StubSVNClient(
        fileLogsByRequest: [
            [makeLog(revision: "1")],
            [makeLog(revision: "2")],
        ],
        fileLogGatesByRequest: [firstGate]
    )
    let store = makeStore(projects: [project], client: client)

    let first = Task { await store.loadFileHistory(for: "느린-보고서.hwp") }
    await firstGate.waitUntilEntered()
    await store.loadFileHistory(for: "최신-보고서.hwp")
    await firstGate.release()
    await first.value

    #expect(store.fileHistoryPath == "최신-보고서.hwp")
    #expect(store.fileHistory.map(\.revision) == ["2"])
    #expect(store.fileHistoryRequest?.projectID == project.id)
    #expect(store.fileHistoryRequest?.relativePath == "최신-보고서.hwp")
}

@MainActor
@Test func projectSwitchClearsProjectOwnedPresentationState() {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/reset-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/reset-second")
    let store = makeStore(projects: [first, second])
    store.isShowingPathRecovery = true
    store.pathRecoveryPreview = SVNRecoveryPreview(mappings: [], ignoredAliasCount: 1, blockingPaths: [])
    store.pathRecoverySourceProjectID = first.id
    store.isShowingUpdatePreview = true
    store.isShowingFileHistory = true
    store.isShowingLocks = true
    store.isShowingIgnoreRules = true
    store.isShowingCredentials = true

    store.selectedProjectID = second.id

    #expect(!store.isShowingPathRecovery)
    #expect(store.pathRecoveryPreview == nil)
    #expect(store.pathRecoverySourceProjectID == nil)
    #expect(!store.isShowingUpdatePreview)
    #expect(!store.isShowingFileHistory)
    #expect(!store.isShowingLocks)
    #expect(!store.isShowingIgnoreRules)
    #expect(!store.isShowingCredentials)
}

@MainActor
@Test func staleDocumentOpenRequestCannotOpenPathInNewProject() async throws {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/open-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/open-second")
    let opener = StubWorkspaceOpener()
    let store = makeStore(
        projects: [first, second],
        workspaceOpener: opener,
        settingsDefaults: makeDocumentOpenPolicyDefaults(.askEveryTime)
    )
    await store.prepareToOpen(path: "보고서.hwp")
    let request = try #require(store.documentOpenRequest)

    store.selectedProjectID = second.id
    store.openWithoutLock(request)

    #expect(opener.openedURLs.isEmpty)
}

@MainActor
@Test func cleanupCompletionAfterProjectSwitchDoesNotOverwriteNewProjectState() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/cleanup-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/cleanup-second")
    let gate = AsyncTestGate()
    let client = StubSVNClient(cleanupGate: gate)
    let store = makeStore(projects: [first, second], client: client)
    store.requestSelectedWorkingCopyCleanup()

    let cleanup = Task { await store.cleanupSelectedWorkingCopy() }
    await gate.waitUntilEntered()
    store.selectedProjectID = second.id
    store.notice = "둘째 프로젝트 알림"
    store.errorMessage = "둘째 프로젝트 오류"
    await gate.release()
    _ = await cleanup.value

    #expect(store.notice == "둘째 프로젝트 알림")
    #expect(store.errorMessage == "둘째 프로젝트 오류")
}

@MainActor
@Test func projectRegistrationDoesNotStealNewerUserSelection() async {
    let first = SVNProject(name: "기존 프로젝트", path: "/tmp/register-existing-first")
    let second = SVNProject(name: "사용자 선택", path: "/tmp/register-existing-second")
    let registrationURL = URL(fileURLWithPath: "/tmp/register-new", isDirectory: true)
    let gate = AsyncTestGate()
    let client = StubSVNClient(validateWorkingCopyGatesByPath: [registrationURL.path: gate])
    let store = makeStore(projects: [first, second], client: client)

    let registration = Task { await store.registerProjects([registrationURL]) }
    await gate.waitUntilEntered()
    store.selectedProjectID = second.id
    store.errorMessage = "둘째 프로젝트 오류"
    await gate.release()
    await registration.value

    #expect(store.projects.contains(where: { $0.path == registrationURL.path }))
    #expect(store.selectedProjectID == second.id)
    #expect(store.errorMessage == "둘째 프로젝트 오류")
}

@MainActor
@Test func multipleProjectRegistrationSelectsFirstInputDeterministically() async {
    let existing = SVNProject(name: "기존 프로젝트", path: "/tmp/register-existing")
    let firstURL = URL(fileURLWithPath: "/tmp/register-batch-first", isDirectory: true)
    let secondURL = URL(fileURLWithPath: "/tmp/register-batch-second", isDirectory: true)
    let store = makeStore(projects: [existing])

    await store.registerProjects([firstURL, secondURL])

    #expect(store.projects.map(\.path).suffix(2) == [firstURL.path, secondURL.path])
    #expect(store.selectedProject?.path == firstURL.path)
}

@MainActor
@Test func staleProjectRegistrationFailureDoesNotOverwriteNewProjectError() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/register-failure-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/register-failure-second")
    let registrationURL = URL(fileURLWithPath: "/tmp/register-failure-new", isDirectory: true)
    let gate = AsyncTestGate()
    let client = StubSVNClient(
        validateWorkingCopyGatesByPath: [registrationURL.path: gate],
        validateWorkingCopyErrorsByPath: [registrationURL.path: TestError.automaticRefreshFailed]
    )
    let store = makeStore(projects: [first, second], client: client)

    let registration = Task { await store.registerProjects([registrationURL]) }
    await gate.waitUntilEntered()
    store.selectedProjectID = second.id
    store.errorMessage = "둘째 프로젝트 오류"
    await gate.release()
    await registration.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.errorMessage == "둘째 프로젝트 오류")
}

@MainActor
@Test func commitWarningRefreshCannotOverwriteNewProjectNotice() async {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/commit-warning-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/commit-warning-second")
    let entry = SVNStatusEntry(path: "보고서.hwp", item: .modified)
    let client = StubSVNClient(
        delaysByPath: [first.path: .milliseconds(100)],
        commitCompletedWarning: (output: "Committed revision 8.", details: "검증 경고")
    )
    let store = makeStore(projects: [first, second], client: client)
    store.statuses = [entry]
    store.selectedPaths = [entry.path]

    let commit = Task { await store.commit(message: "보고서 수정") }
    for _ in 0..<100 {
        if await client.snapshotRequestCount() > 0 { break }
        await Task.yield()
    }
    store.selectedProjectID = second.id
    store.notice = "둘째 프로젝트 알림"
    _ = await commit.value

    #expect(store.notice == "둘째 프로젝트 알림")
}

@MainActor
@Test func pathRecoveryRefreshCannotOverwriteLaterProjectNotice() async {
    let source = SVNProject(name: "복구 원본", path: "/tmp/recovery-source")
    let other = SVNProject(name: "다른 프로젝트", path: "/tmp/recovery-other")
    let recoveredPath = "/tmp/recovered-concurrency"
    let client = StubSVNClient(
        delaysByPath: [recoveredPath: .milliseconds(100)],
        recoveryResult: SVNRecoveryResult(
            destinationPath: recoveredPath,
            snapshot: SVNWorkingCopySnapshot(
                statuses: [],
                revision: SVNWorkingCopyRevision(minimum: "1", maximum: "1"),
                collisions: [],
                versionedPathsByCanonicalKey: [:]
            ),
            migratedPaths: []
        )
    )
    let store = makeStore(projects: [source, other], client: client)
    store.pathRecoverySourceProjectID = source.id

    let recovery = Task {
        await store.recoverWorkingCopy(
            to: URL(fileURLWithPath: "/tmp/recovery-destination", isDirectory: true)
        )
    }
    for _ in 0..<100 {
        if await client.snapshotRequestCount() > 0 { break }
        await Task.yield()
    }
    store.selectedProjectID = other.id
    store.notice = "다른 프로젝트 알림"
    _ = await recovery.value

    #expect(store.notice == "다른 프로젝트 알림")
}

@MainActor
@Test func pathRecoveryCompletionDoesNotStealLaterProjectSelection() async {
    let source = SVNProject(name: "복구 원본", path: "/tmp/recovery-steal-source")
    let other = SVNProject(name: "다른 프로젝트", path: "/tmp/recovery-steal-other")
    let recoveredPath = "/tmp/recovered-without-selection-steal"
    let gate = AsyncTestGate()
    let client = StubSVNClient(
        recoveryResult: SVNRecoveryResult(
            destinationPath: recoveredPath,
            snapshot: SVNWorkingCopySnapshot(
                statuses: [],
                revision: SVNWorkingCopyRevision(minimum: "1", maximum: "1"),
                collisions: [],
                versionedPathsByCanonicalKey: [:]
            ),
            migratedPaths: []
        ),
        recoveryGate: gate
    )
    let store = makeStore(projects: [source, other], client: client)
    store.pathRecoverySourceProjectID = source.id

    let recovery = Task {
        await store.recoverWorkingCopy(
            to: URL(fileURLWithPath: "/tmp/recovery-steal-destination", isDirectory: true)
        )
    }
    await gate.waitUntilEntered()
    store.selectedProjectID = other.id
    store.notice = "다른 프로젝트 알림"
    await gate.release()
    _ = await recovery.value

    #expect(store.projects.contains(where: { $0.path == recoveredPath }))
    #expect(store.selectedProjectID == other.id)
    #expect(store.notice == "다른 프로젝트 알림")
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
                .ui.conflict.resolvedReviewFileBeforeCommitting
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
@Test func treeConflictCreatesTreeSessionWithoutContentSession() async throws {
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
    #expect(store.activeTreeConflictSession?.details.type == "tree")
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func propertyConflictCreatesPropertySessionWithoutOtherSessions() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details(replacingTypeWith: "property"))
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: fixture.details.path)

    #expect(store.activeConflictSession == nil)
    #expect(store.activeTreeConflictSession == nil)
    #expect(store.recoveryState.propertyConflictSession?.details.type == "property")
    #expect(store.errorMessage == nil)
}

@MainActor
@Test func unknownConflictTypeRemainsUnsupported() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details(replacingTypeWith: "future-type"))
    let store = makeStore(
        projects: [fixture.project],
        client: client,
        conflictFileService: ConflictFileService(backupRootURL: fixture.backupRoot)
    )

    await store.prepareConflictResolution(for: fixture.details.path)

    #expect(store.activeConflictSession == nil)
    #expect(store.activeTreeConflictSession == nil)
    #expect(store.recoveryState.propertyConflictSession == nil)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func treeKeepWorkingStateResolvesWithWorkingChoice() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details(replacingTypeWith: "tree"))
    let store = makeStore(projects: [fixture.project], client: client)
    await store.prepareConflictResolution(for: fixture.details.path)

    await store.resolveActiveTreeConflict(using: .keepWorkingState)

    #expect(await client.lastConflictChoice() == .working)
    #expect(await client.conflictOperationNames() == ["resolve"])
    #expect(store.activeTreeConflictSession == nil)
}

@MainActor
@Test func treeRestoreServerVersionRevertsBeforeUpdating() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let client = StubSVNClient(conflictDetailsValue: fixture.details(replacingTypeWith: "tree"))
    let store = makeStore(projects: [fixture.project], client: client)
    await store.prepareConflictResolution(for: fixture.details.path)

    await store.resolveActiveTreeConflict(using: .restoreServerVersion)

    #expect(await client.conflictOperationNames() == ["revert", "update"])
    #expect(await client.requestedReverts().map(\.relativePath) == [fixture.details.path])
    #expect(store.activeTreeConflictSession == nil)
}

@MainActor
@Test func treeResolveKeepsSessionWhenConflictRemains() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let treeDetails = fixture.details(replacingTypeWith: "tree")
    let conflictedSnapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: treeDetails.path, item: .conflicted, revision: "42")],
        revision: SVNWorkingCopyRevision(minimum: "42", maximum: "42"),
        collisions: [],
        versionedPathsByCanonicalKey: [treeDetails.path: [treeDetails.path]]
    )
    let client = StubSVNClient(
        snapshotsByPath: [fixture.project.path: conflictedSnapshot],
        postResolveSnapshotsByPath: [fixture.project.path: conflictedSnapshot],
        conflictDetailsValue: treeDetails
    )
    let store = makeStore(projects: [fixture.project], client: client)
    await store.prepareConflictResolution(for: treeDetails.path)
    let session = try #require(store.activeTreeConflictSession)

    await store.resolveActiveTreeConflict(using: .keepWorkingState)

    #expect(store.activeTreeConflictSession == session)
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func canonicalAliasTreeConflictUsesExactVersionedPath() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let versionedPath = "문서/주간보고서.hwp"
    let selectedPath = versionedPath.decomposedStringWithCanonicalMapping
    let details = SVNConflictDetails(path: versionedPath, type: "tree", operation: "update")
    let snapshot = SVNWorkingCopySnapshot(
        statuses: [SVNStatusEntry(path: versionedPath, item: .conflicted, revision: "42")],
        revision: SVNWorkingCopyRevision(minimum: "42", maximum: "42"),
        collisions: [],
        versionedPathsByCanonicalKey: [versionedPath: [versionedPath]]
    )
    let client = StubSVNClient(
        snapshotsByPath: [fixture.project.path: snapshot],
        conflictDetailsByRelativePath: [versionedPath: details]
    )
    let store = makeStore(projects: [fixture.project], client: client)

    await store.prepareConflictResolution(for: selectedPath)
    let session = try #require(store.activeTreeConflictSession)

    #expect(Data(session.requestedPath.utf8) == Data(selectedPath.utf8))
    #expect(Data(session.versionedPath.utf8) == Data(versionedPath.utf8))
    #expect(session.wasCanonicallyResolved)
    await store.resolveActiveTreeConflict(using: .keepWorkingState)
    #expect(await client.lastResolvedPath().map { Data($0.utf8) } == Data(versionedPath.utf8))
}

@MainActor
@Test func treeResolveCompletionAfterProjectSwitchDoesNotMutateNewProject() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    let otherProject = SVNProject(name: "다른 프로젝트", path: fixture.root.appendingPathComponent("other").path)
    let resolveGate = AsyncTestGate()
    let client = StubSVNClient(
        conflictDetailsValue: fixture.details(replacingTypeWith: "tree"),
        resolveGate: resolveGate
    )
    let store = makeStore(projects: [fixture.project, otherProject], client: client)
    await store.prepareConflictResolution(for: fixture.details.path)

    let resolution = Task { await store.resolveActiveTreeConflict(using: .keepWorkingState) }
    await resolveGate.waitUntilEntered()
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
@Test func treeRestoreUsesSavedCredentialsAndCertificateSetting() async throws {
    let fixture = try ProjectStoreConflictFixture()
    defer { fixture.remove() }
    var project = fixture.project
    project.username = "tester"
    project.allowsUntrustedServerCertificate = true
    let client = StubSVNClient(conflictDetailsValue: fixture.details(replacingTypeWith: "tree"))
    let store = makeStore(projects: [project], client: client)
    store.sessionPasswords[project.id] = "secret"
    await store.prepareConflictResolution(for: fixture.details.path)

    await store.resolveActiveTreeConflict(using: .restoreServerVersion)

    #expect(await client.lastRevertCredentialUsername() == "tester")
    #expect(await client.lastUpdateCredentialUsername() == "tester")
    #expect(await client.lastUpdateAllowedUntrustedCertificate() == true)
}

@MainActor
@Test func updateForwardsOnlySelectedProjectsAllowedCertificateFailures() async {
    let allowedProject = SVNProject(
        name: "허용 프로젝트",
        path: "/tmp/allowed-certificate-project",
        allowsUntrustedServerCertificate: true,
        allowedServerCertificateFailures: [.expired]
    )
    let deniedProject = SVNProject(
        name: "미허용 프로젝트",
        path: "/tmp/denied-certificate-project"
    )
    let client = StubSVNClient()
    let store = makeStore(projects: [allowedProject, deniedProject], client: client)

    await store.update()
    store.selectedProjectID = deniedProject.id
    await store.update()

    #expect(await client.updateAllowedCertificateFailures() == [
        [
            .expired,
            .unknownCertificateAuthority,
            .commonNameMismatch,
        ],
        [],
    ])
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
    await olderGate.waitUntilEntered()
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
    await resolveGate.waitUntilEntered()
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
    await resolveGate.waitUntilEntered()
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
    await resolveGate.waitUntilEntered()
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
    await resolveGate.waitUntilEntered()
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
    store.workingCopyFileTree = [makeBrowserRefreshNode("Folder", directory: true, hasChildren: true)]
    var browserTreeState = store.workingCopyBrowserTreeState
    browserTreeState.expandedPaths = ["Folder"]
    store.workingCopyBrowserTreeState = browserTreeState
    store.selectedBrowserPath = "Folder"

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
    #expect(store.workingCopyBrowserTreeState.expandedPaths.isEmpty)
    #expect(store.selectedBrowserPath == nil)
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
@Test func refreshingFileBrowserRestoresExpandedDirectoriesAndSelectionShallowestFirst() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-expansion-refresh")
    let fileService = RecordingWorkingCopyFileService(contentsByDirectory: [
        "": [makeBrowserRefreshNode("Folder", directory: true, hasChildren: true)],
        "Folder": [
            makeBrowserRefreshNode("Folder/Nested", directory: true, hasChildren: true),
            makeBrowserRefreshNode("Folder/fresh.txt"),
        ],
        "Folder/Nested": [makeBrowserRefreshNode("Folder/Nested/deep.txt")],
    ])
    let store = makeStore(projects: [project], fileService: fileService)
    store.workingCopyFileTree = [makeBrowserRefreshNode(
        "Folder",
        directory: true,
        children: [
            makeBrowserRefreshNode(
                "Folder/Nested",
                directory: true,
                children: [makeBrowserRefreshNode("Folder/Nested/deep.txt")]
            ),
            makeBrowserRefreshNode("Folder/stale.txt"),
        ]
    )]
    var state = store.workingCopyBrowserTreeState
    state.expandedPaths = ["Folder", "Folder/Nested", "Removed"]
    store.workingCopyBrowserTreeState = state
    store.selectedBrowserPath = "Folder/Nested/deep.txt"

    await store.loadWorkingCopyFiles()

    #expect(await fileService.requestedDirectories() == ["", "Folder", "Folder/Nested"])
    #expect(store.workingCopyBrowserTreeState.expandedPaths == ["Folder", "Folder/Nested"])
    #expect(store.workingCopyBrowserTreeState.childrenByDirectory["Folder"]?.map(\.relativePath) == [
        "Folder/Nested",
        "Folder/fresh.txt",
    ])
    #expect(store.workingCopyBrowserTreeState.node(at: "Folder/stale.txt") == nil)
    #expect(store.selectedBrowserPath == "Folder/Nested/deep.txt")
}

@MainActor
@Test func refreshingFileBrowserKeepsPublishedTreeUntilAtomicReplacement() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-atomic-refresh")
    let folderGate = AsyncTestGate()
    let fileService = ControlledWorkingCopyFileService(
        contentsByDirectory: [
            "": [makeBrowserRefreshNode("Folder", directory: true, hasChildren: true)],
            "Folder": [makeBrowserRefreshNode("Folder/fresh.txt")],
        ],
        gatesByDirectory: ["Folder": folderGate]
    )
    let store = makeStore(projects: [project], fileService: fileService)
    store.workingCopyFileTree = [makeBrowserRefreshNode(
        "Folder",
        directory: true,
        children: [makeBrowserRefreshNode("Folder/original.txt")]
    )]
    var originalState = store.workingCopyBrowserTreeState
    originalState.expandedPaths = ["Folder"]
    store.workingCopyBrowserTreeState = originalState
    store.selectedBrowserPath = "Folder/original.txt"

    let refresh = Task { await store.loadWorkingCopyFiles() }
    await folderGate.waitUntilEntered()

    #expect(store.workingCopyBrowserTreeState == originalState)
    #expect(store.workingCopyBrowserTreeState.visibleRows().map(\.relativePath) == [
        "Folder",
        "Folder/original.txt",
    ])
    #expect(store.selectedBrowserPath == "Folder/original.txt")

    await folderGate.release()
    await refresh.value

    #expect(store.workingCopyBrowserTreeState.visibleRows().map(\.relativePath) == [
        "Folder",
        "Folder/fresh.txt",
    ])
    #expect(store.selectedBrowserPath == nil)
}

@MainActor
@Test func failedFileBrowserRefreshKeepsExistingTreeExpansionAndSelection() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-failed-refresh")
    let fileService = ControlledWorkingCopyFileService(
        contentsByDirectory: [
            "": [makeBrowserRefreshNode("Folder", directory: true, hasChildren: true)],
        ],
        failingDirectories: ["Folder"]
    )
    let store = makeStore(projects: [project], fileService: fileService)
    store.workingCopyFileTree = [makeBrowserRefreshNode(
        "Folder",
        directory: true,
        children: [makeBrowserRefreshNode("Folder/original.txt")]
    )]
    var originalState = store.workingCopyBrowserTreeState
    originalState.expandedPaths = ["Folder"]
    store.workingCopyBrowserTreeState = originalState
    store.selectedBrowserPath = "Folder/original.txt"

    await store.loadWorkingCopyFiles()

    #expect(store.workingCopyBrowserTreeState == originalState)
    #expect(store.selectedBrowserPath == "Folder/original.txt")
    #expect(store.errorMessage != nil)
}

@MainActor
@Test func fileBrowserRefreshPreservesExpansionChangesMadeWhileLoading() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-interaction-refresh")
    let folderGate = AsyncTestGate()
    let fileService = ControlledWorkingCopyFileService(
        contentsByDirectory: [
            "": [
                makeBrowserRefreshNode("First", directory: true, hasChildren: true),
                makeBrowserRefreshNode("Second", directory: true, hasChildren: true),
            ],
            "First": [makeBrowserRefreshNode("First/fresh.txt")],
        ],
        gatesByDirectory: ["First": folderGate]
    )
    let store = makeStore(projects: [project], fileService: fileService)
    store.workingCopyFileTree = [
        makeBrowserRefreshNode(
            "First",
            directory: true,
            children: [makeBrowserRefreshNode("First/original.txt")]
        ),
        makeBrowserRefreshNode(
            "Second",
            directory: true,
            children: [makeBrowserRefreshNode("Second/kept.txt")]
        ),
    ]
    var state = store.workingCopyBrowserTreeState
    state.expandedPaths = ["First"]
    store.workingCopyBrowserTreeState = state

    let refresh = Task { await store.loadWorkingCopyFiles() }
    await folderGate.waitUntilEntered()
    _ = store.setWorkingCopyDirectory("First", expanded: false)
    _ = store.setWorkingCopyDirectory("Second", expanded: true)
    store.selectedBrowserPath = "Second/kept.txt"
    await folderGate.release()
    await refresh.value

    #expect(store.workingCopyBrowserTreeState.expandedPaths == ["Second"])
    #expect(store.workingCopyBrowserTreeState.childrenByDirectory["Second"]?.map(\.relativePath) == [
        "Second/kept.txt",
    ])
    #expect(store.selectedBrowserPath == "Second/kept.txt")
}

@MainActor
@Test func directoryLoadStartedDuringRefreshRebasesOntoAtomicReplacement() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-rebased-directory-load")
    let refreshGate = AsyncTestGate()
    let userLoadGate = AsyncTestGate()
    let fileService = ControlledWorkingCopyFileService(
        contentsByDirectory: [
            "": [
                makeBrowserRefreshNode("First", directory: true, hasChildren: true),
                makeBrowserRefreshNode("Second", directory: true, hasChildren: true),
            ],
            "First": [makeBrowserRefreshNode("First/fresh.txt")],
            "Second": [makeBrowserRefreshNode("Second/loaded.txt")],
        ],
        gatesByDirectory: [
            "First": refreshGate,
            "Second": userLoadGate,
        ]
    )
    let store = makeStore(projects: [project], fileService: fileService)
    var state = WorkingCopyBrowserTreeState()
    state.reset(rootNodes: [
        makeBrowserRefreshNode("First", directory: true, hasChildren: true),
        makeBrowserRefreshNode("Second", directory: true, hasChildren: true),
    ])
    state.cache([makeBrowserRefreshNode("First/original.txt")], for: "First")
    state.expandedPaths = ["First"]
    store.workingCopyBrowserTreeState = state

    let refresh = Task { await store.loadWorkingCopyFiles() }
    await refreshGate.waitUntilEntered()
    _ = store.setWorkingCopyDirectory("First", expanded: false)
    let directoryToLoad = store.setWorkingCopyDirectory("Second", expanded: true)
    #expect(directoryToLoad == "Second")
    let userLoad = Task { await store.loadWorkingCopyDirectory("Second") }
    await userLoadGate.waitUntilEntered()

    await refreshGate.release()
    await refresh.value
    #expect(store.workingCopyBrowserTreeState.expandedPaths == ["Second"])
    #expect(!store.workingCopyBrowserTreeState.hasCachedChildren(for: "Second"))

    await userLoadGate.release()
    await userLoad.value
    #expect(store.workingCopyBrowserTreeState.childrenByDirectory["Second"]?.map(\.relativePath) == [
        "Second/loaded.txt",
    ])
}

@MainActor
@Test func refreshingFileBrowserClearsSelectionWhenRestoredPathDisappears() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/browser-selection-refresh")
    let fileService = RecordingWorkingCopyFileService(contentsByDirectory: ["": []])
    let store = makeStore(projects: [project], fileService: fileService)
    store.workingCopyFileTree = [makeBrowserRefreshNode(
        "Removed",
        directory: true,
        children: [makeBrowserRefreshNode("Removed/file.txt")]
    )]
    var state = store.workingCopyBrowserTreeState
    state.expandedPaths = ["Removed"]
    store.workingCopyBrowserTreeState = state
    store.selectedBrowserPath = "Removed/file.txt"

    await store.loadWorkingCopyFiles()

    #expect(store.workingCopyBrowserTreeState.expandedPaths.isEmpty)
    #expect(store.selectedBrowserPath == nil)
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
@Test func documentOpenPolicyChoosesPromptOpenOrLockAndOpen() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")

    for policy in DocumentOpenLockPolicy.allCases {
        let defaults = makeDocumentOpenPolicyDefaults(policy)
        let opener = StubWorkspaceOpener()
        let client = StubSVNClient()
        let store = makeStore(
            projects: [project],
            client: client,
            workspaceOpener: opener,
            settingsDefaults: defaults
        )

        await store.prepareToOpen(path: "policy.docx", isVersioned: true)

        switch policy {
        case .askEveryTime:
            #expect(store.documentOpenRequest?.relativePath == "policy.docx")
            #expect(opener.openedURLs.isEmpty)
            #expect(await client.requestedLockPaths().isEmpty)
        case .alwaysOpenWithoutLock:
            #expect(store.documentOpenRequest == nil)
            #expect(opener.openedURLs.map(\.lastPathComponent) == ["policy.docx"])
            #expect(await client.requestedLockPaths().isEmpty)
        case .alwaysLockAndOpen:
            #expect(store.documentOpenRequest == nil)
            #expect(opener.openedURLs.map(\.lastPathComponent) == ["policy.docx"])
            #expect(await client.requestedLockPaths() == ["policy.docx"])
        }
    }
}

@MainActor
@Test func alwaysLockAndOpenOpensWithoutLockAndNamesTheOtherOwner() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project", username: "tester")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient(lockInfoByPath: [
        "shared.xlsx": SVNLockInfo(path: "shared.xlsx", owner: "other-user"),
    ])
    let store = makeStore(
        projects: [project],
        client: client,
        workspaceOpener: opener,
        settingsDefaults: makeDocumentOpenPolicyDefaults(.alwaysLockAndOpen)
    )

    await store.prepareToOpen(path: "shared.xlsx", isVersioned: true)

    #expect(await client.requestedLockPaths().isEmpty)
    #expect(opener.openedURLs.map(\.lastPathComponent) == ["shared.xlsx"])
    #expect(store.documentOpenRequest == nil)
    #expect(store.notice?.contains("other-user") == true)
}

@MainActor
@Test func documentLockedByCurrentUserOpensImmediatelyForEveryPolicy() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project", username: "tester")

    for policy in DocumentOpenLockPolicy.allCases {
        let opener = StubWorkspaceOpener()
        let client = StubSVNClient(lockInfoByPath: [
            "owned.pptx": SVNLockInfo(path: "owned.pptx", owner: "tester"),
        ])
        let store = makeStore(
            projects: [project],
            client: client,
            workspaceOpener: opener,
            settingsDefaults: makeDocumentOpenPolicyDefaults(policy)
        )

        await store.prepareToOpen(path: "owned.pptx", isVersioned: true)

        #expect(opener.openedURLs.map(\.lastPathComponent) == ["owned.pptx"])
        #expect(store.documentOpenRequest == nil)
        #expect(await client.requestedLockPaths().isEmpty)
    }
}

@MainActor
@Test func rememberingOpenWithoutLockUsesTheSettingsPolicyAndCanBeReset() {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let defaults = makeDocumentOpenPolicyDefaults(.askEveryTime)
    let store = makeStore(projects: [project], settingsDefaults: defaults)
    let request = DocumentOpenRequest(
        projectID: project.id,
        relativePath: "remember.docx",
        repositoryRelativePath: "remember.docx",
        existingLock: nil
    )

    store.openWithoutLock(request, rememberingChoice: true)
    #expect(AppSettings.documentOpenLockPolicy(in: defaults) == .alwaysOpenWithoutLock)

    AppSettings.setDocumentOpenLockPolicy(.askEveryTime, in: defaults)
    #expect(AppSettings.documentOpenLockPolicy(in: defaults) == .askEveryTime)
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
    #expect(request.lockInformationWasUnavailable)
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
@Test func updateLocalSummaryCountsPropertyConflictsOncePerPath() {
    let project = SVNProject(name: "프로젝트", path: "/tmp/property-conflict-badge")
    let store = makeStore(projects: [project])

    store.updateLocalSummary(
        for: project.id,
        statuses: [
            SVNStatusEntry(
                path: "속성만.txt",
                item: .unknown("normal"),
                propertyState: .conflicted
            ),
            SVNStatusEntry(
                path: "둘다.txt",
                item: .conflicted,
                propertyState: .conflicted
            ),
            SVNStatusEntry(
                path: "텍스트만.txt",
                item: .conflicted,
                propertyState: .none
            ),
            SVNStatusEntry(
                path: "수정.txt",
                item: .modified,
                propertyState: .modified
            ),
        ]
    )

    #expect(store.projectSummaries[project.id]?.conflictCount == 3)
}

@MainActor
@Test func updateBadgeRefreshIncludesUnselectedProjects() async {
    let selected = SVNProject(name: "선택", path: "/tmp/badge-selected")
    let unselected = SVNProject(name: "비선택", path: "/tmp/badge-unselected")
    let client = StubSVNClient(
        revisionsByPath: [selected.path: "10", unselected.path: "20"],
        outOfDateByPath: [selected.path: false, unselected.path: true]
    )
    let store = makeStore(projects: [selected, unselected], client: client)

    await store.refreshUpdateBadges()

    #expect(store.projectSummaries[selected.id]?.needsUpdate == false)
    #expect(store.projectSummaries[unselected.id]?.needsUpdate == true)
}

@MainActor
@Test func updateBadgesRefreshOnConfiguredInterval() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/badge-interval")
    let sleeper = RecordingUpdateBadgeSleeper(stopsAfter: 2)
    let client = StubSVNClient(
        revisionsByPath: [project.path: "10"],
        outOfDateByPath: [project.path: true]
    )
    let store = makeStore(
        projects: [project],
        client: client,
        updateBadgeRefreshInterval: .milliseconds(10),
        updateBadgeSleep: { duration in
            try await sleeper.sleep(for: duration)
        }
    )

    await sleeper.waitUntilRecorded(2)

    #expect(await sleeper.recordedDurations() == [.milliseconds(10), .milliseconds(10)])
    #expect(store.projectSummaries[project.id]?.needsUpdate == true)
}

@MainActor
@Test func updateBadgePollingBacksOffAndResetsAfterSuccess() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/badge-backoff")
    let sleeper = RecordingUpdateBadgeSleeper(stopsAfter: 5)
    let client = StubSVNClient(
        revisionsByPath: [project.path: "10"],
        outOfDateByPath: [project.path: true],
        updateBadgeFailuresRemaining: 3
    )
    let store = makeStore(
        projects: [project],
        client: client,
        updateBadgeRefreshInterval: .milliseconds(10),
        updateBadgeMaximumRefreshInterval: .milliseconds(40),
        updateBadgeSleep: { duration in
            try await sleeper.sleep(for: duration)
        }
    )

    await sleeper.waitUntilRecorded(5)

    #expect(await sleeper.recordedDurations() == [
        .milliseconds(10),
        .milliseconds(20),
        .milliseconds(40),
        .milliseconds(40),
        .milliseconds(10),
    ])
    #expect(store.projectSummaries[project.id]?.needsUpdate == true)
}

@MainActor
@Test func blockedSelectedProjectDoesNotBlockOtherUpdateBadges() async {
    let selected = SVNProject(name: "차단 프로젝트", path: "/tmp/badge-blocked-selected")
    let unselected = SVNProject(name: "정상 프로젝트", path: "/tmp/badge-unselected-after-block")
    let client = StubSVNClient(
        revisionsByPath: [selected.path: "10", unselected.path: "20"],
        outOfDateByPath: [selected.path: false, unselected.path: true],
        snapshotError: TestError.automaticRefreshFailed
    )
    let store = makeStore(
        projects: [selected, unselected],
        client: client,
        fileService: StubWorkingCopyFileService(delaysByPath: [:])
    )

    await store.refreshSelectedProject(manual: false)
    store.updateRemoteSummary(for: unselected.id, needsUpdate: false)

    await store.refreshSelectedProject(manual: false)

    #expect(store.projectSummaries[unselected.id]?.needsUpdate == true)
    #expect(await client.snapshotRequestCount() == 1)
}

@MainActor
@Test func refreshKeepsKnownUpdateBadgeWhileRequestIsRunning() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/badge-flicker")
    let client = StubSVNClient(
        revisionsByPath: [project.path: "10"],
        delaysByPath: [project.path: .milliseconds(100)],
        outOfDateByPath: [project.path: true]
    )
    let store = makeStore(projects: [project], client: client)
    store.isWorkingCopyOutOfDate = true
    store.updateRemoteSummary(for: project.id, needsUpdate: true)

    let refresh = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.isWorkingCopyOutOfDate == true)
    #expect(store.projectSummaries[project.id]?.needsUpdate == true)

    await refresh.value
}

@MainActor
@Test func remoteStatusDeterminesUpdateBadge() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/badge-remote-status")
    let client = StubSVNClient(
        revisionsByPath: [project.path: "10"],
        latestLogRevisionsByPath: [project.path: "9"],
        outOfDateByPath: [project.path: true]
    )
    let store = makeStore(projects: [project], client: client)

    await store.refresh()

    #expect(store.isWorkingCopyOutOfDate == true)
    #expect(store.projectSummaries[project.id]?.needsUpdate == true)
}

@MainActor
@Test func lateUpdateBadgeResponseDoesNotOverwriteNewProjectState() async {
    let first = SVNProject(name: "느린 프로젝트", path: "/tmp/slow-badge")
    let second = SVNProject(name: "빠른 프로젝트", path: "/tmp/fast-badge")
    let client = StubSVNClient(
        revisionsByPath: [first.path: "10", second.path: "20"],
        latestLogRevisionsByPath: [first.path: "11", second.path: "20"],
        delaysByPath: [first.path: .milliseconds(100)],
        outOfDateByPath: [first.path: true, second.path: false]
    )
    let store = makeStore(projects: [first, second], client: client)

    let staleRefresh = Task { await store.refresh() }
    try? await Task.sleep(for: .milliseconds(20))
    store.selectedProjectID = second.id
    await store.refresh()
    await staleRefresh.value

    #expect(store.selectedProjectID == second.id)
    #expect(store.isWorkingCopyOutOfDate == false)
    #expect(store.projectSummaries[second.id]?.needsUpdate == false)
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
    #expect(await client.workingCopyEntriesRequestCount() == 1)
    #expect(await client.repositoryLocksRequestCount() == 1)
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
    #expect(store.errorMessage == nil)
    #expect(store.isShowingUpdatePreview)
    #expect(store.recoveryState.outOfDateCommitRecoveryRequest?.message == "디렉터리 삭제")
    #expect(store.recoveryState.outOfDateCommitRecoveryRequest?.paths == ["generated"])
    #expect(store.localizedError(
        SVNError.workingCopyOutOfDate(details: details),
        language: .english
    ).contains("Run Update") == true)
}

@MainActor
@Test func updateConflictDoesNotRetryOutOfDateCommit() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/out-of-date-update-conflict")
    let details = "svn: E155011: Directory '.' is out of date"
    let conflictSnapshot = SVNWorkingCopySnapshot(
        statuses: [
            SVNStatusEntry(
                path: ".",
                item: .conflicted,
                revision: "2",
                nodeKind: .directory,
                propertyState: .conflicted
            ),
        ],
        revision: SVNWorkingCopyRevision(minimum: "2", maximum: "2"),
        collisions: [],
        versionedPathsByCanonicalKey: [:]
    )
    let client = StubSVNClient(
        postResolveSnapshotsByPath: [project.path: conflictSnapshot],
        commitErrors: [.workingCopyOutOfDate(details: details)]
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = [
        SVNStatusEntry(
            path: ".",
            item: .modified,
            revision: "1",
            nodeKind: .directory,
            propertyState: .modified
        ),
    ]
    store.selectedPaths = ["."]

    #expect(!(await store.commit(message: "무시 규칙 추가")))
    await store.update()

    #expect(await client.commitRequestCount() == 1)
    let recovery = try #require(store.recoveryState.outOfDateCommitRecoveryRequest)
    #expect(recovery.message == "무시 규칙 추가")
    #expect(recovery.paths == ["."])
    #expect(recovery.conflictedPaths == ["."])
    #expect(store.isShowingUpdatePreview)
}

@MainActor
@Test func authenticationResumeContinuesUpdateBeforeRetryingCommit() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/out-of-date-update-auth")
    let modifiedSnapshot = SVNWorkingCopySnapshot(
        statuses: [
            SVNStatusEntry(
                path: ".",
                item: .modified,
                revision: "2",
                nodeKind: .directory,
                propertyState: .modified
            ),
        ],
        revision: SVNWorkingCopyRevision(minimum: "2", maximum: "2"),
        collisions: [],
        versionedPathsByCanonicalKey: [:]
    )
    let client = StubSVNClient(
        postResolveSnapshotsByPath: [project.path: modifiedSnapshot],
        commitErrors: [.workingCopyOutOfDate(details: "svn: E155011: out of date")],
        updateErrors: [.accessDenied]
    )
    let store = makeStore(projects: [project], client: client)
    store.statuses = modifiedSnapshot.statuses
    store.selectedPaths = ["."]

    #expect(!(await store.commit(message: "무시 규칙 추가")))
    await store.update()
    let request = try #require(store.authenticationRequest)
    #expect(request.action == .commit(message: "무시 규칙 추가"))
    #expect(!store.isShowingUpdatePreview)

    await store.retryKeychainAccess(for: request)

    #expect(await client.updateRequestCount() == 2)
    #expect(await client.commitRequestCount() == 2)
    #expect(await client.lastCommitRequest()?.paths == ["."])
    #expect(await client.lastCommitRequest()?.message == "무시 규칙 추가")
    #expect(store.recoveryState.outOfDateCommitRecoveryRequest == nil)
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

    // 새로고침 하나가 refresh, browseFiles, lock 작업을 함께 띄운다.
    // 개수를 고정하면 새로고침 구성이 바뀔 때마다 깨지므로, 겹친 두 호출이
    // 모두 같은 프로젝트의 refresh 작업을 등록했는지와 바쁨 상태 유지만 확인한다.
    #expect(store.isWorking)
    #expect(store.activeOperations.filter { $0.kind == .refresh(project.id) }.count == 2)

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

    let previewID = store.beginOperation(.previewUpdate(selected.id))
    #expect(store.isSelectedProjectActionBlocked)
    store.endOperation(previewID)

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
    await client.waitUntilCheckoutStarts()
    store.cancelCheckout()
    let succeeded = await checkout.value

    #expect(!succeeded)
    #expect(store.projects.isEmpty)
    #expect(!store.isCheckingOut)
    #expect(store.errorMessage == nil)
    #expect(store.canceledCheckoutRecoveryRequest?.destinationPath == destination.path)
    #expect(!accessManager.releasedURLs.contains(destination))
}

@MainActor
@Test func canceledCheckoutCanRegisterCleanupAndContinueUpdating() async throws {
    let client = StubSVNClient(checkoutRunsUntilCancelled: true)
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(),
        projectAccessManager: StubProjectAccessManager(),
        projectPathChecker: StubProjectPathChecker(),
        updateBadgeRefreshInterval: nil
    )
    let destination = URL(fileURLWithPath: "/tmp/canceled-checkout-resume", isDirectory: true)
    let checkout = Task {
        await store.startCheckout(
            repositoryURL: "https://example.test/svn/project",
            destinationURL: destination,
            username: "tester",
            password: "",
            allowsUntrustedServerCertificate: false
        )
    }
    await client.waitUntilCheckoutStarts()
    store.cancelCheckout()
    _ = await checkout.value
    let request = try #require(store.canceledCheckoutRecoveryRequest)

    #expect(await store.resumeCanceledCheckout(request))
    #expect(store.projects.map(\.path) == [destination.path])
    #expect(store.selectedProject?.path == destination.path)
    #expect(await client.cleanupRequestCount() == 1)
    #expect(await client.updateRequestCount() == 1)
    #expect(store.canceledCheckoutRecoveryRequest == nil)
}

@MainActor
@Test func olderCanceledCheckoutValidationCannotOverwriteNewerRecoveryRequest() async throws {
    let firstDestination = URL(fileURLWithPath: "/tmp/canceled-checkout-first", isDirectory: true)
    let secondDestination = URL(fileURLWithPath: "/tmp/canceled-checkout-second", isDirectory: true)
    let firstValidationGate = AsyncTestGate()
    let secondValidationGate = AsyncTestGate()
    let client = StubSVNClient(
        checkoutRunsUntilCancelled: true,
        validateWorkingCopyGatesByPath: [
            firstDestination.path: firstValidationGate,
            secondDestination.path: secondValidationGate,
        ]
    )
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(),
        projectAccessManager: StubProjectAccessManager(),
        projectPathChecker: StubProjectPathChecker(),
        updateBadgeRefreshInterval: nil
    )

    let firstCheckout = Task {
        await store.startCheckout(
            repositoryURL: "https://example.test/svn/first",
            destinationURL: firstDestination,
            username: "",
            password: "",
            allowsUntrustedServerCertificate: false
        )
    }
    await client.waitUntilCheckoutStarts()
    store.cancelCheckout()
    await firstValidationGate.waitUntilEntered()

    let secondCheckout = Task {
        await store.startCheckout(
            repositoryURL: "https://example.test/svn/second",
            destinationURL: secondDestination,
            username: "",
            password: "",
            allowsUntrustedServerCertificate: false
        )
    }
    await client.waitUntilCheckoutStarts(2)
    store.cancelCheckout()
    await secondValidationGate.waitUntilEntered()
    await secondValidationGate.release()
    _ = await secondCheckout.value
    #expect(store.canceledCheckoutRecoveryRequest?.destinationPath == secondDestination.path)

    await firstValidationGate.release()
    _ = await firstCheckout.value
    #expect(store.canceledCheckoutRecoveryRequest?.destinationPath == secondDestination.path)
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
@Test func credentialWriteFailureKeepsStoredProjectAuthenticationSettings() {
    let project = SVNProject(
        name: "프로젝트",
        path: "/tmp/project",
        username: "old-user",
        allowsUntrustedServerCertificate: false,
        allowedServerCertificateFailures: [.expired]
    )
    let credentials = StubCredentialStore(setError: TestError.credentialWriteFailed)
    let persistence = MemoryProjectPersistence(projects: [project])
    let store = ProjectStore(
        credentialStore: credentials,
        persistence: persistence,
        projectAccessManager: StubProjectAccessManager(),
        updateBadgeRefreshInterval: nil
    )

    #expect(!store.saveCredentials(
        for: project.id,
        username: "new-user",
        newPassword: "new-secret",
        allowsUntrustedServerCertificate: true
    ))

    #expect(store.projects == [project])
    #expect(persistence.savedProjects == [project])
}

@MainActor
@Test func authenticationRetryKeychainFailureKeepsStoredUsername() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project", username: "old-user")
    let credentials = StubCredentialStore(setError: TestError.credentialWriteFailed)
    let store = ProjectStore(
        credentialStore: credentials,
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: StubProjectAccessManager(),
        updateBadgeRefreshInterval: nil
    )
    let request = SVNAuthenticationRequest(projectID: project.id, action: .retryManually)
    store.authenticationRequest = request

    let succeeded = await store.useCredentials(
        for: request,
        username: "new-user",
        password: "new-secret",
        saveInKeychain: true
    )

    #expect(!succeeded)
    #expect(store.projects == [project])
    #expect(store.authenticationRequest == request)
}

@MainActor
@Test func folderSettingsCredentialFailureKeepsPathAndAuthenticationSettings() async {
    let project = SVNProject(name: "이전 폴더", path: "/tmp/old", username: "old-user")
    let client = StubSVNClient(
        verifyCredentialsError: SVNError.commandFailed(command: "svn info", message: "E215004")
    )
    let store = ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: StubProjectAccessManager(),
        updateBadgeRefreshInterval: nil
    )

    let result = await store.saveFolderSettings(
        for: project.id,
        destinationURL: URL(fileURLWithPath: "/tmp/new", isDirectory: true),
        username: "new-user",
        newPassword: "wrong",
        allowsUntrustedServerCertificate: true
    )

    guard case .credentialFailure = result else {
        Issue.record("Expected credential failure, got \(result)")
        return
    }
    #expect(store.projects == [project])
}

@MainActor
@Test func folderSettingsKeychainFailureKeepsPathAndAuthenticationSettings() async {
    let project = SVNProject(name: "이전 폴더", path: "/tmp/old", username: "old-user")
    let credentials = StubCredentialStore(setError: TestError.credentialWriteFailed)
    let store = ProjectStore(
        client: StubSVNClient(),
        credentialStore: credentials,
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: StubProjectAccessManager(),
        updateBadgeRefreshInterval: nil
    )

    let result = await store.saveFolderSettings(
        for: project.id,
        destinationURL: URL(fileURLWithPath: "/tmp/new", isDirectory: true),
        username: "new-user",
        newPassword: "new-secret",
        allowsUntrustedServerCertificate: true
    )

    #expect(result == .failed)
    #expect(store.projects == [project])
}

@MainActor
@Test func folderSettingsCommitPathAndAuthenticationAfterAllRiskySteps() async throws {
    let project = SVNProject(name: "이전 폴더", path: "/tmp/old", username: "old-user")
    let destination = URL(fileURLWithPath: "/tmp/new", isDirectory: true)
    let credentials = StubCredentialStore()
    let accessManager = StubProjectAccessManager()
    let client = StubSVNClient()
    let store = ProjectStore(
        client: client,
        credentialStore: credentials,
        persistence: MemoryProjectPersistence(projects: [project]),
        projectAccessManager: accessManager,
        updateBadgeRefreshInterval: nil
    )

    let result = await store.saveFolderSettings(
        for: project.id,
        destinationURL: destination,
        username: "new-user",
        newPassword: "new-secret",
        allowsUntrustedServerCertificate: true
    )

    let updatedProject = try #require(store.projects.first)
    #expect(result == .saved)
    #expect(updatedProject.path == destination.path)
    #expect(updatedProject.name == "new")
    #expect(updatedProject.username == "new-user")
    #expect(updatedProject.allowsUntrustedServerCertificate == true)
    #expect(try credentials.password(for: project.id) == "new-secret")
    #expect(accessManager.accessedURLs[project.id] == destination)
    #expect(await client.recordedVerifiedPaths() == [destination.path])
}

@MainActor
@Test func allowingCertificateFailureResumesTheFailedUpdate() async throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client)
    let certificateError = SVNError.commandFailed(
        command: "svn update",
        message: "svn: E230001: Server SSL certificate verification failed: certificate has expired"
    )
    store.handleRemoteError(certificateError, project: project, action: .update)
    let request = try #require(store.authenticationRequest)

    await store.allowServerCertificateFailure(for: request)

    #expect(await client.updateRequestCount() == 1)
    #expect(store.authenticationRequest == nil)
    #expect(store.allowedServerCertificateFailures(for: store.projects[0]).contains(.expired))
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
@Test func pathRecoverySheetCannotCloseWhileRecoveryIsRunning() {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let store = makeStore(projects: [project])
    store.pathRecoverySourceProjectID = project.id
    store.isShowingPathRecovery = true
    let operationID = store.beginOperation(.recover(project.id))

    store.isShowingPathRecovery = false

    #expect(store.isShowingPathRecovery)

    store.endOperation(operationID)
    store.isShowingPathRecovery = false

    #expect(!store.isShowingPathRecovery)
}

@MainActor
@Test func temporaryFileCleanupSheetCannotCloseWhileCleanupIsRunning() {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let store = makeStore(projects: [project])
    store.isShowingTemporaryFileCleanup = true
    let operationID = store.beginOperation(.cleanupTemporaryFiles(project.id))

    store.isShowingTemporaryFileCleanup = false

    #expect(store.isShowingTemporaryFileCleanup)

    store.endOperation(operationID)
    store.isShowingTemporaryFileCleanup = false

    #expect(!store.isShowingTemporaryFileCleanup)
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

@MainActor
@Test func commitHistoryPreparesExistingRevisionActionsForWorkingCopyFile() throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let store = makeStore(projects: [project])
    let deletedPath = SVNChangedPath(
        path: "/project/trunk/docs/%E1%84%87%E1%85%A9%E1%84%80%E1%85%A9%E1%84%89%E1%85%A5.xlsx",
        action: .deleted,
        kind: .file
    )
    store.workingCopyRepositoryPath = "/project/trunk"

    store.prepareHistoryRevisionActions(revision: "42", changedPath: deletedPath)

    let context = try #require(store.recoveryState.historyRevisionActionContext)
    #expect(context.selectedRevision == "42")
    #expect(context.contentRevision == "41")
    #expect(context.repositoryPath == deletedPath.path)
    #expect(context.fileHistoryRequest.projectID == project.id)
    #expect(context.fileHistoryRequest.relativePath == "docs/보고서.xlsx")
    #expect(store.fileHistoryRequest == context.fileHistoryRequest)

    store.requestHistoryRevisionRestore(revision: context.contentRevision)

    let restoreRequest = try #require(store.recoveryState.historyRevisionRestoreRequest)
    #expect(restoreRequest.fileHistoryRequestID == context.fileHistoryRequest.id)
    #expect(restoreRequest.projectID == project.id)
    #expect(restoreRequest.relativePath == "docs/보고서.xlsx")
    #expect(restoreRequest.revision == "41")
}

@MainActor
@Test func commitHistoryPreparationPreservesTheOpenFileHistoryRequest() throws {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let store = makeStore(projects: [project])
    let fileHistoryRequest = FileHistoryRequest(
        projectID: project.id,
        relativePath: "docs/현재-기록.xlsx"
    )
    store.fileHistoryRequest = fileHistoryRequest
    store.workingCopyRepositoryPath = "/project/trunk"
    store.routeNextFileHistoryRequestToCommitHistory()

    store.prepareHistoryRevisionActions(
        revision: "42",
        changedPath: SVNChangedPath(
            path: "/project/trunk/docs/과거-기록.xlsx",
            action: .modified,
            kind: .file
        )
    )

    let context = try #require(store.recoveryState.historyRevisionActionContext)
    #expect(store.fileHistoryRequest == fileHistoryRequest)
    #expect(context.fileHistoryRequest != fileHistoryRequest)

    store.requestCommitHistoryRevisionRestore(
        fileHistoryRequest: context.fileHistoryRequest,
        revision: context.contentRevision
    )
    #expect(
        store.recoveryState.historyRevisionRestoreRequest?.fileHistoryRequestID
            == context.fileHistoryRequest.id
    )
}

@MainActor
@Test func commitHistoryDoesNotOfferRevisionActionsOutsideWorkingCopyRoot() {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let store = makeStore(projects: [project])
    store.workingCopyRepositoryPath = "/project/trunk"

    store.prepareHistoryRevisionActions(
        revision: "42",
        changedPath: SVNChangedPath(
            path: "/project/branches/other/report.xlsx",
            action: .modified,
            kind: .file
        )
    )

    #expect(store.recoveryState.historyRevisionActionContext == nil)
    #expect(store.fileHistoryRequest == nil)
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
@Test func repositoryTemporaryFileCleanupRejectsDuplicateExecution() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("repository-cleanup-duplicate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])
        .write(to: root.appendingPathComponent(".DS_Store"))
    let project = SVNProject(name: "프로젝트", path: root.path)
    let gate = AsyncTestGate()
    let client = StubSVNClient(commitGate: gate)
    let store = makeStore(projects: [project], client: client)
    store.temporaryFileCleanupAssessments = TemporaryFilePolicy.validateRepositoryCleanupCandidates(
        paths: [".DS_Store"],
        in: root
    )
    store.selectedTemporaryFileCleanupPaths = [".DS_Store"]

    let first = Task { await store.confirmRepositoryTemporaryFileCleanup() }
    await gate.waitUntilEntered()
    let second = Task { await store.confirmRepositoryTemporaryFileCleanup() }
    for _ in 0..<100 {
        if await client.commitRequestCount() == 2 { break }
        await Task.yield()
    }
    await gate.release()
    await first.value
    await second.value

    #expect(await client.commitRequestCount() == 1)
    #expect(await client.requestedRepositoryCleanupDeletionPaths() == [".DS_Store"])
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
@Test func partialGitIgnoreApplicationRefreshesAppliedAndPendingRules() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-gitignore-partial-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("/build/\n/cache/\n".utf8)
        .write(to: directory.appendingPathComponent(".gitignore"))

    let project = SVNProject(name: "프로젝트", path: directory.path)
    let client = StubSVNClient(addIgnoreRuleFailureAtRequest: 2)
    let store = makeStore(projects: [project], client: client)
    await store.compareGitIgnore()
    store.selectedGitIgnoreImportIDs = store.selectableGitIgnoreImportIDs

    await store.applySelectedGitIgnoreRules()

    #expect(await client.requestedAddedIgnoreRules().count == 1)
    #expect(store.gitIgnoreImportItems.count == 2)
    #expect(store.gitIgnoreImportItems.filter(\.isSelectable).count == 1)
    #expect(store.selectedGitIgnoreImportIDs.count == 1)
    #expect(store.errorMessage != nil)
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
@Test func deletionCompletionAfterRefreshDoesNotPublishIntoAnotherProject() async throws {
    let first = SVNProject(name: "첫 프로젝트", path: "/tmp/delete-race-first")
    let second = SVNProject(name: "둘째 프로젝트", path: "/tmp/delete-race-second")
    let missing = SVNStatusEntry(path: "old.txt", item: .missing, revision: "10")
    let refreshGate = AsyncTestGate()
    let client = StubSVNClient(snapshotGate: refreshGate)
    let store = makeStore(projects: [first, second], client: client)
    store.statuses = [missing]
    store.requestDeletion(missing)
    let request = try #require(store.deletionRequest)

    let deletion = Task { await store.confirmDeletion(request) }
    await refreshGate.waitUntilEntered()
    store.selectedProjectID = second.id
    let secondStatus = SVNStatusEntry(path: "second.txt", item: .modified, revision: "20")
    store.statuses = [secondStatus]
    await refreshGate.release()
    await deletion.value

    #expect(store.statuses == [secondStatus])
    #expect(store.selectedPaths.isEmpty)
    #expect(store.notice == nil)
}

@MainActor
@Test func repositoryRelocationOperationAppearsInFolderSettingsProgress() {
    let store = makeStore(projects: [SVNProject(name: "프로젝트", path: "/tmp/project")])
    let operationID = store.beginOperation(.relocateRepository(store.projects[0].id))

    #expect(store.isRelocatingProject)

    store.endOperation(operationID)
    #expect(!store.isRelocatingProject)
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
    settingsDefaults: UserDefaults = UserDefaults(suiteName: "project-store-settings-\(UUID().uuidString)")!,
    hideTemporaryFiles: Bool = true,
    updateBadgeRefreshInterval: Duration? = nil,
    updateBadgeMaximumRefreshInterval: Duration = .seconds(15 * 60),
    updateBadgeSleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
        try await Task.sleep(for: duration)
    }
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
        settingsDefaults: settingsDefaults,
        hideTemporaryFiles: hideTemporaryFiles,
        updateBadgeRefreshInterval: updateBadgeRefreshInterval,
        updateBadgeMaximumRefreshInterval: updateBadgeMaximumRefreshInterval,
        updateBadgeSleep: updateBadgeSleep
    )
}

private func makeDocumentOpenPolicyDefaults(
    _ policy: DocumentOpenLockPolicy
) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "document-open-policy-\(UUID().uuidString)")!
    AppSettings.setDocumentOpenLockPolicy(policy, in: defaults)
    return defaults
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
    private var didEnter = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isReleased else { return }
        didEnter = true
        let pendingEntryWaiters = entryWaiters
        entryWaiters.removeAll()
        pendingEntryWaiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        let pending = releaseWaiters
        releaseWaiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor RecordingUpdateBadgeSleeper {
    private let stopsAfter: Int
    private var durations: [Duration] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(stopsAfter: Int) {
        self.stopsAfter = stopsAfter
    }

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
        let pending = waiters.filter { $0.count <= durations.count }
        waiters.removeAll { $0.count <= durations.count }
        pending.forEach { $0.continuation.resume() }
        if durations.count == stopsAfter {
            throw CancellationError()
        }
    }

    func waitUntilRecorded(_ count: Int) async {
        guard durations.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func recordedDurations() -> [Duration] {
        durations
    }
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

private actor StubSVNClient: SVNClientServing, MultiplePathLockServing {
    let statusesByPath: [String: [SVNStatusEntry]]
    let revisionsByPath: [String: String]
    let latestLogRevisionsByPath: [String: String]
    let delaysByPath: [String: Duration]
    let outOfDateByPath: [String: Bool]
    private var updateBadgeFailuresRemaining: Int
    let remoteChangesByPath: [String: [SVNStatusEntry]]
    let fileLogsByPath: [String: [SVNLogEntry]]
    private var fileLogsByRequest: [[SVNLogEntry]]
    private var fileLogGatesByRequest: [AsyncTestGate]
    let checkoutResult: String
    let checkoutProgress: [String]
    let checkoutRunsUntilCancelled: Bool
    let validateWorkingCopyError: Error?
    let validateWorkingCopyGatesByPath: [String: AsyncTestGate]
    let validateWorkingCopyErrorsByPath: [String: Error]
    let verifyCredentialsError: Error?
    private var checkoutStartCount = 0
    private var checkoutStartWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var validatedPaths: [String] = []
    private var verifiedCredentials: [SVNCredentials?] = []
    private var verifiedPaths: [String] = []
    let lockInfoByPath: [String: SVNLockInfo]
    let lockInfoError: Error?
    let snapshotError: Error?
    let snapshotGate: AsyncTestGate?
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
    let addIgnoreRuleFailureAtRequest: Int?
    let commitError: SVNError?
    private var commitErrors: [SVNError]
    let repositoryPathNormalizationTargetsValue: [SVNRepositoryPathNormalizationTarget]
    let repositoryPathNormalizationResultValue: SVNRepositoryPathNormalizationResult?
    let repositoryPathNormalizationError: SVNRepositoryPathNormalizationError?
    let repositoryPathNormalizationScanError: Error?
    let repositoryPathNormalizationScanGate: AsyncTestGate?
    let cleanupError: Error?
    let cleanupGate: AsyncTestGate?
    let unlockErrorWhenNotForced: Error?
    let forcedUnlockGate: AsyncTestGate?
    private var revertGatesByRequest: [AsyncTestGate]
    private var revertErrorsByRequest: [TestError?]
    let commitGate: AsyncTestGate?
    let recoveryGate: AsyncTestGate?
    let multiplePathLockGate: AsyncTestGate?
    private var updatePreviewCommitsByRequest: [[SVNLogEntry]]
    private var updatePreviewGatesByRequest: [AsyncTestGate]
    private var updatePreviewRequests = 0
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
    private var fileLogRequests = 0
    private var conflictChoices: [SVNConflictChoice] = []
    private var conflictOperations: [String] = []
    private var conflictDetailsRequestCounts: [String: Int] = [:]
    private var revertCalls: [RevertCall] = []
    private var revertRequests = 0
    private var conflictDetailsRequestRawPaths: [Data] = []
    private var resolvedPaths: [String] = []
    private var addedIgnoreRules: [SVNIgnoreRule] = []
    private var scheduleDeletionRequests = 0
    private var repositoryPathNormalizationScanRequests = 0
    private var repositoryPathNormalizationRequests = 0
    private var updateRequests = 0
    private var updateErrors: [KeychainStoreError]
    private var revertCredentialUsernames: [String?] = []
    private var updateCredentialUsernames: [String?] = []
    private var updateAllowedUntrustedCertificates: [Bool] = []
    private var recordedUpdateAllowedCertificateFailures: [Set<SVNServerCertificateFailure>] = []
    private var repositoryCleanupDeletionPaths: [String] = []
    private var commitRequests: [CommitRequest] = []
    private var cleanupRequests = 0
    private var unlockForces: [Bool] = []
    private var multiplePathLockRequests = 0

    init(
        statusesByPath: [String: [SVNStatusEntry]] = [:],
        revisionsByPath: [String: String] = [:],
        latestLogRevisionsByPath: [String: String] = [:],
        delaysByPath: [String: Duration] = [:],
        outOfDateByPath: [String: Bool] = [:],
        updateBadgeFailuresRemaining: Int = 0,
        remoteChangesByPath: [String: [SVNStatusEntry]] = [:],
        fileLogsByPath: [String: [SVNLogEntry]] = [:],
        fileLogsByRequest: [[SVNLogEntry]] = [],
        fileLogGatesByRequest: [AsyncTestGate] = [],
        checkoutResult: String = "checked out",
        checkoutProgress: [String] = [],
        checkoutRunsUntilCancelled: Bool = false,
        validateWorkingCopyError: Error? = nil,
        validateWorkingCopyGatesByPath: [String: AsyncTestGate] = [:],
        validateWorkingCopyErrorsByPath: [String: Error] = [:],
        verifyCredentialsError: Error? = nil,
        lockInfoByPath: [String: SVNLockInfo] = [:],
        lockInfoError: Error? = nil,
        snapshotError: Error? = nil,
        snapshotGate: AsyncTestGate? = nil,
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
        addIgnoreRuleFailureAtRequest: Int? = nil,
        commitError: SVNError? = nil,
        commitErrors: [SVNError] = [],
        updateErrors: [KeychainStoreError] = [],
        repositoryPathNormalizationTargets: [SVNRepositoryPathNormalizationTarget] = [],
        repositoryPathNormalizationResult: SVNRepositoryPathNormalizationResult? = nil,
        repositoryPathNormalizationError: SVNRepositoryPathNormalizationError? = nil,
        repositoryPathNormalizationScanError: Error? = nil,
        repositoryPathNormalizationScanGate: AsyncTestGate? = nil,
        cleanupError: Error? = nil,
        cleanupGate: AsyncTestGate? = nil,
        unlockErrorWhenNotForced: Error? = nil,
        forcedUnlockGate: AsyncTestGate? = nil,
        revertGatesByRequest: [AsyncTestGate] = [],
        revertErrorsByRequest: [TestError?] = [],
        commitGate: AsyncTestGate? = nil,
        recoveryGate: AsyncTestGate? = nil,
        multiplePathLockGate: AsyncTestGate? = nil,
        updatePreviewCommitsByRequest: [[SVNLogEntry]] = [],
        updatePreviewGatesByRequest: [AsyncTestGate] = []
    ) {
        self.statusesByPath = statusesByPath
        self.revisionsByPath = revisionsByPath
        self.latestLogRevisionsByPath = latestLogRevisionsByPath
        self.delaysByPath = delaysByPath
        self.outOfDateByPath = outOfDateByPath
        self.updateBadgeFailuresRemaining = updateBadgeFailuresRemaining
        self.remoteChangesByPath = remoteChangesByPath
        self.fileLogsByPath = fileLogsByPath
        self.fileLogsByRequest = fileLogsByRequest
        self.fileLogGatesByRequest = fileLogGatesByRequest
        self.checkoutResult = checkoutResult
        self.checkoutProgress = checkoutProgress
        self.checkoutRunsUntilCancelled = checkoutRunsUntilCancelled
        self.validateWorkingCopyError = validateWorkingCopyError
        self.validateWorkingCopyGatesByPath = validateWorkingCopyGatesByPath
        self.validateWorkingCopyErrorsByPath = validateWorkingCopyErrorsByPath
        self.verifyCredentialsError = verifyCredentialsError
        self.lockInfoByPath = lockInfoByPath
        self.lockInfoError = lockInfoError
        self.snapshotError = snapshotError
        self.snapshotGate = snapshotGate
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
        self.commitErrors = commitErrors
        self.updateErrors = updateErrors
        repositoryPathNormalizationTargetsValue = repositoryPathNormalizationTargets
        repositoryPathNormalizationResultValue = repositoryPathNormalizationResult
        self.repositoryPathNormalizationError = repositoryPathNormalizationError
        self.repositoryPathNormalizationScanError = repositoryPathNormalizationScanError
        self.repositoryPathNormalizationScanGate = repositoryPathNormalizationScanGate
        self.cleanupError = cleanupError
        self.cleanupGate = cleanupGate
        self.unlockErrorWhenNotForced = unlockErrorWhenNotForced
        self.forcedUnlockGate = forcedUnlockGate
        self.revertGatesByRequest = revertGatesByRequest
        self.revertErrorsByRequest = revertErrorsByRequest
        self.commitGate = commitGate
        self.recoveryGate = recoveryGate
        self.multiplePathLockGate = multiplePathLockGate
        self.updatePreviewCommitsByRequest = updatePreviewCommitsByRequest
        self.updatePreviewGatesByRequest = updatePreviewGatesByRequest
        workingCopyEntriesValue = workingCopyEntries
        ignoreRulesValue = ignoreRules
        self.addIgnoreRuleFailureAtRequest = addIgnoreRuleFailureAtRequest
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

    func checkout(repositoryURL: String, destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String { checkoutResult }
    func checkout(repositoryURL: String, destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>, progress: SVNOutputHandler?) async throws -> String {
        for output in checkoutProgress { progress?(output) }
        if checkoutRunsUntilCancelled {
            checkoutStartCount += 1
            let pending = checkoutStartWaiters.filter { $0.count <= checkoutStartCount }
            checkoutStartWaiters.removeAll { $0.count <= checkoutStartCount }
            pending.forEach { $0.continuation.resume() }
            // 실제 SVNClient는 취소 시 svn 프로세스를 종료하고 CancellationError를
            // 던집니다. sleep도 같은 오류를 던지므로 취소 경로를 그대로 재현합니다.
            try await Task.sleep(for: .seconds(60))
        }
        return checkoutResult
    }
    func validateWorkingCopy(at path: String, credentials: SVNCredentials?) async throws {
        validatedPaths.append(path)
        await validateWorkingCopyGatesByPath[path]?.wait()
        if let error = validateWorkingCopyErrorsByPath[path] { throw error }
        if let validateWorkingCopyError { throw validateWorkingCopyError }
    }
    func cleanup(at path: String, credentials: SVNCredentials?) async throws -> String {
        cleanupRequests += 1
        await cleanupGate?.wait()
        if let cleanupError { throw cleanupError }
        return "cleaned"
    }
    func cleanupRequestCount() -> Int { cleanupRequests }

    func verifyCredentials(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws {
        verifiedPaths.append(path)
        verifiedCredentials.append(credentials)
        if let verifyCredentialsError { throw verifyCredentialsError }
    }

    func recordedVerifiedCredentials() -> [SVNCredentials?] { verifiedCredentials }
    func recordedVerifiedPaths() -> [String] { verifiedPaths }
    func recordedValidatedPaths() -> [String] { validatedPaths }
    func waitUntilCheckoutStarts(_ count: Int = 1) async {
        guard checkoutStartCount < count else { return }
        await withCheckedContinuation { continuation in
            checkoutStartWaiters.append((count, continuation))
        }
    }
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
        await snapshotGate?.wait()
        await delay(for: path)
        if let snapshotError { throw snapshotError }
        if !conflictOperations.isEmpty, let snapshot = postResolveSnapshotsByPath[path] { return snapshot }
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
    func recoverWorkingCopy(from sourcePath: String, to destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> SVNRecoveryResult {
        recoveryPaths = [sourcePath, destinationPath]
        await recoveryGate?.wait()
        return recoveryResultValue
    }
    func repositoryPathsNeedingNormalization(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNRepositoryPathNormalizationTarget] {
        repositoryPathNormalizationScanRequests += 1
        await repositoryPathNormalizationScanGate?.wait()
        if let repositoryPathNormalizationScanError { throw repositoryPathNormalizationScanError }
        return repositoryPathNormalizationTargetsValue
    }
    func repositoryEntries(at repositoryURL: String, revision: String?, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNRepositoryEntry] { [] }
    func normalizeRepositoryPaths(_ targets: [SVNRepositoryPathNormalizationTarget], at path: String, message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> SVNRepositoryPathNormalizationResult {
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
    func ignoreRules(at path: String, credentials: SVNCredentials?) async throws -> [SVNIgnoreRule] {
        ignoreRulesValue + addedIgnoreRules
    }
    func addIgnoreRule(at path: String, directory: String, pattern: String, propertyKind: SVNIgnorePropertyKind, credentials: SVNCredentials?) async throws {
        if addedIgnoreRules.count + 1 == addIgnoreRuleFailureAtRequest {
            throw TestError.credentialWriteFailed
        }
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
    func repositoryLocks(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNLockInfo] {
        repositoryLocksRequests += 1
        await delay(for: path)
        if let error = repositoryLocksErrorsByPath[path] { throw error }
        return repositoryLocksByPath[path] ?? []
    }
    func lockInfo(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> SVNLockInfo? {
        lockInfoRequests += 1
        lockInfoPaths.append(relativePath)
        if let lockInfoError { throw lockInfoError }
        return lockInfoByPath[relativePath]
    }
    func lockInfoRequestCount() -> Int { lockInfoRequests }
    func requestedLockInfoPaths() -> [String] { lockInfoPaths }
    func lock(at path: String, relativePath: String, comment: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        lockPaths.append(relativePath)
        return "locked"
    }
    func lock(at path: String, relativePaths: [String], comment: String, force: Bool, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        multiplePathLockRequests += 1
        await multiplePathLockGate?.wait()
        return "locked"
    }
    func multiplePathLockRequestCount() -> Int { multiplePathLockRequests }
    func requestedLockPaths() -> [String] { lockPaths }
    func unlock(at path: String, relativePath: String, force: Bool, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        unlockForces.append(force)
        if !force, let unlockErrorWhenNotForced { throw unlockErrorWhenNotForced }
        if force { await forcedUnlockGate?.wait() }
        return "unlocked"
    }
    func requestedUnlockForces() -> [Bool] { unlockForces }
    func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> SVNConflictDetails? {
        conflictDetailsRequestCounts[relativePath, default: 0] += 1
        conflictDetailsRequestRawPaths.append(Data(relativePath.utf8))
        if let gate = conflictDetailsGatesByRelativePath[relativePath] { await gate.wait() }
        await delay(for: path)
        return conflictDetailsByRelativePath[relativePath] ?? conflictDetailsValue
    }
    func resolveConflict(at path: String, relativePath: String, choice: SVNConflictChoice, credentials: SVNCredentials?) async throws -> String {
        conflictOperations.append("resolve")
        conflictChoices.append(choice)
        resolvedPaths.append(relativePath)
        if let resolveGate { await resolveGate.wait() }
        if let resolveError { throw resolveError }
        return "resolved"
    }
    func lastConflictChoice() -> SVNConflictChoice? { conflictChoices.last }
    func lastResolvedPath() -> String? { resolvedPaths.last }
    func conflictChoiceCount() -> Int { conflictChoices.count }
    func conflictOperationNames() -> [String] { conflictOperations }
    func conflictDetailsRequestCount(for path: String) -> Int { conflictDetailsRequestCounts[path, default: 0] }
    func exactConflictDetailsRequestCount(for path: String) -> Int {
        conflictDetailsRequestRawPaths.filter { $0 == Data(path.utf8) }.count
    }
    func log(at path: String, limit: Int, endingAtRevision: String?, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNLogEntry] {
        logRequests += 1
        await delay(for: path)
        return [makeLog(revision: latestLogRevisionsByPath[path] ?? revisionsByPath[path] ?? "0")]
    }
    func updatePreviewIncomingCommits(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNLogEntry] {
        let requestIndex = updatePreviewRequests
        updatePreviewRequests += 1
        let commits = updatePreviewCommitsByRequest.indices.contains(requestIndex)
            ? updatePreviewCommitsByRequest[requestIndex]
            : []
        let gate = updatePreviewGatesByRequest.indices.contains(requestIndex)
            ? updatePreviewGatesByRequest[requestIndex]
            : nil
        await gate?.wait()
        await delay(for: path)
        return commits
    }
    func revisionDiff(at path: String, revision: String, repositoryPath: String, workingCopyRepositoryPath: String?, pegRevision: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        revisionDiffRequests.append(RevisionDiffRequest(
            revision: revision,
            repositoryPath: repositoryPath,
            workingCopyRepositoryPath: workingCopyRepositoryPath,
            pegRevision: pegRevision
        ))
        return "revision diff"
    }
    func lastRevisionDiffRequest() -> RevisionDiffRequest? { revisionDiffRequests.last }
    func fileContents(at path: String, relativePath: String, revision: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> Data {
        throw RevisionFileError.historyClientUnavailable
    }
    func export(at path: String, relativePath: String, revision: String, destinationPath: String, force: Bool, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        throw RevisionFileError.historyClientUnavailable
    }
    func workingCopyRevision(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopyRevision {
        await delay(for: path)
        let revision = revisionsByPath[path] ?? "0"
        return SVNWorkingCopyRevision(minimum: revision, maximum: revision)
    }
    func workingCopyRepositoryPath(at path: String, credentials: SVNCredentials?) async throws -> String { "/trunk" }
    func workingCopyIsOutOfDate(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> Bool {
        outOfDateRequests += 1
        await delay(for: path)
        if updateBadgeFailuresRemaining > 0 {
            updateBadgeFailuresRemaining -= 1
            throw TestError.automaticRefreshFailed
        }
        return outOfDateByPath[path] ?? false
    }
    func remoteChanges(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNStatusEntry] {
        await delay(for: path)
        return remoteChangesByPath[path] ?? []
    }
    func update(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String {
        conflictOperations.append("update")
        updateCredentialUsernames.append(credentials?.username)
        updateAllowedUntrustedCertificates.append(allowUntrustedServerCertificate)
        updateRequests += 1
        if !updateErrors.isEmpty { throw updateErrors.removeFirst() }
        return "updated"
    }
    func update(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        recordedUpdateAllowedCertificateFailures.append(allowedServerCertificateFailures)
        return try await update(
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
    }
    func updateRequestCount() -> Int { updateRequests }
    func lastUpdateCredentialUsername() -> String? { updateCredentialUsernames.last ?? nil }
    func lastUpdateAllowedUntrustedCertificate() -> Bool? { updateAllowedUntrustedCertificates.last }
    func updateAllowedCertificateFailures() -> [Set<SVNServerCertificateFailure>] {
        recordedUpdateAllowedCertificateFailures
    }
    func diff(at path: String, relativePath: String?, credentials: SVNCredentials?) async throws -> String { "diff" }
    func revert(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> String {
        let requestIndex = revertRequests
        revertRequests += 1
        let requestGate = revertGatesByRequest.indices.contains(requestIndex)
            ? revertGatesByRequest[requestIndex]
            : nil
        let requestError = revertErrorsByRequest.indices.contains(requestIndex)
            ? revertErrorsByRequest[requestIndex]
            : nil
        conflictOperations.append("revert")
        revertCredentialUsernames.append(credentials?.username)
        await requestGate?.wait()
        await delay(for: path)
        revertCalls.append(RevertCall(workingCopyPath: path, relativePath: relativePath))
        if let requestError { throw requestError }
        return "reverted"
    }
    func requestedReverts() -> [RevertCall] { revertCalls }
    func lastRevertCredentialUsername() -> String? { revertCredentialUsernames.last ?? nil }
    func fileLog(at path: String, relativePath: String, limit: Int, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> [SVNLogEntry] {
        let requestIndex = fileLogRequests
        fileLogRequests += 1
        let requestLogs = fileLogsByRequest.indices.contains(requestIndex)
            ? fileLogsByRequest[requestIndex]
            : nil
        let requestGate = fileLogGatesByRequest.indices.contains(requestIndex)
            ? fileLogGatesByRequest[requestIndex]
            : nil
        await delay(for: path)
        await requestGate?.wait()
        return requestLogs ?? fileLogsByPath[path] ?? []
    }
    func commit(at path: String, paths: [String], message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, allowedServerCertificateFailures: Set<SVNServerCertificateFailure>) async throws -> String {
        commitRequests.append(CommitRequest(paths: paths, message: message))
        await commitGate?.wait()
        if let commitCompletedWarning {
            throw SVNError.commitSucceededWithValidationWarning(
                output: commitCompletedWarning.output,
                details: commitCompletedWarning.details
            )
        }
        if !commitErrors.isEmpty { throw commitErrors.removeFirst() }
        if let commitError { throw commitError }
        return "committed"
    }
    func lastCommitRequest() -> CommitRequest? { commitRequests.last }
    func commitRequestCount() -> Int { commitRequests.count }
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

private actor RecordingWorkingCopyFileService: WorkingCopyFileListing {
    let contentsByDirectory: [String: [WorkingCopyFileNode]]
    private var directoryRequests: [String] = []

    init(contentsByDirectory: [String: [WorkingCopyFileNode]]) {
        self.contentsByDirectory = contentsByDirectory
    }

    func tree(
        at rootPath: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) async throws -> [WorkingCopyFileNode] {
        contentsByDirectory[""] ?? []
    }

    func directoryContents(
        at rootPath: String,
        relativeDirectory: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) async throws -> [WorkingCopyFileNode] {
        directoryRequests.append(relativeDirectory)
        return contentsByDirectory[relativeDirectory] ?? []
    }

    func requestedDirectories() -> [String] {
        directoryRequests
    }
}

private actor ControlledWorkingCopyFileService: WorkingCopyFileListing {
    let contentsByDirectory: [String: [WorkingCopyFileNode]]
    let gatesByDirectory: [String: AsyncTestGate]
    let failingDirectories: Set<String>
    private var directoryRequests: [String] = []

    init(
        contentsByDirectory: [String: [WorkingCopyFileNode]],
        gatesByDirectory: [String: AsyncTestGate] = [:],
        failingDirectories: Set<String> = []
    ) {
        self.contentsByDirectory = contentsByDirectory
        self.gatesByDirectory = gatesByDirectory
        self.failingDirectories = failingDirectories
    }

    func tree(
        at rootPath: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) async throws -> [WorkingCopyFileNode] {
        try await directoryContents(
            at: rootPath,
            relativeDirectory: "",
            svnEntries: svnEntries
        )
    }

    func directoryContents(
        at rootPath: String,
        relativeDirectory: String,
        svnEntries: [SVNWorkingCopyEntry]
    ) async throws -> [WorkingCopyFileNode] {
        directoryRequests.append(relativeDirectory)
        await gatesByDirectory[relativeDirectory]?.wait()
        if failingDirectories.contains(relativeDirectory) {
            throw TestError.automaticRefreshFailed
        }
        return contentsByDirectory[relativeDirectory] ?? []
    }

    func requestedDirectories() -> [String] {
        directoryRequests
    }
}

private func makeBrowserRefreshNode(
    _ path: String,
    directory: Bool = false,
    hasChildren: Bool? = nil,
    children: [WorkingCopyFileNode]? = nil
) -> WorkingCopyFileNode {
    WorkingCopyFileNode(
        name: path.split(separator: "/").last.map(String.init) ?? path,
        relativePath: path,
        isDirectory: directory,
        isSymbolicLink: false,
        hasChildren: hasChildren,
        svnEntry: nil,
        children: children
    )
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

@MainActor
@Test func realSVNLocalDeletionTreeConflictKeepsDeletionThroughStore() async throws {
    let fixture = try RealSVNTreeConflictFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()

    // 변경 사항 목록이 이 파일을 충돌로 표시해야 우클릭 메뉴에 충돌 해결이 나온다.
    #expect(try await fixture.snapshotMarksVictimConflicted())

    await store.prepareConflictResolution(for: fixture.victimPath)

    #expect(store.errorMessage == nil)
    #expect(store.activeConflictSession == nil)
    let session = try #require(store.activeTreeConflictSession)
    #expect(session.details.type == "tree")
    #expect(session.details.treeConflictReason == "delete")
    #expect(session.details.treeConflictAction == "edit")

    await store.resolveActiveTreeConflict(using: .keepWorkingState)

    #expect(store.errorMessage == nil)
    #expect(store.activeTreeConflictSession == nil)
    #expect(!FileManager.default.fileExists(atPath: fixture.victimURL.path))
    #expect(try !fixture.hasConflictedVictim())
}

@MainActor
@Test func realSVNLocalDeletionTreeConflictRestoresServerFileThroughStore() async throws {
    let fixture = try RealSVNTreeConflictFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()

    await store.prepareConflictResolution(for: fixture.victimPath)
    #expect(store.activeTreeConflictSession != nil)

    await store.resolveActiveTreeConflict(using: .restoreServerVersion)

    #expect(store.errorMessage == nil)
    #expect(store.activeTreeConflictSession == nil)
    #expect(try !fixture.hasConflictedVictim())
    #expect(
        try Data(contentsOf: fixture.victimURL) == Data("base\nserver edit\n".utf8)
    )
}

/// 사용자가 실제로 겪은 상황을 그대로 만든다.
/// 로컬에서 파일을 삭제한 뒤 서버가 그 파일을 수정한 리비전을 받으면
/// `local delete, incoming edit` 트리 충돌이 남는다.
private final class RealSVNTreeConflictFixture {
    let root: URL
    let workingCopy: URL
    let victimPath = "tree.txt"
    let project: SVNProject
    private let client: SVNClient
    private let svnPath: String

    var victimURL: URL { workingCopy.appendingPathComponent(victimPath) }

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("svn-tree-conflict-store-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let importDirectory = root.appendingPathComponent("import", isDirectory: true)
        let publisher = root.appendingPathComponent("publisher", isDirectory: true)
        workingCopy = root.appendingPathComponent("conflicted", isDirectory: true)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )

        try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        try Data("base\n".utf8).write(to: importDirectory.appendingPathComponent(victimPath))
        _ = try Self.run(svnadminPath, ["create", repository.path])
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        _ = try Self.run(svnPath, ["import", importDirectory.path, repositoryURL, "-m", "initial"])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, publisher.path])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path])

        try Data("base\nserver edit\n".utf8)
            .write(to: publisher.appendingPathComponent(victimPath))
        _ = try Self.run(svnPath, ["commit", publisher.path, "-m", "server edit"])

        project = SVNProject(name: "트리 충돌", path: workingCopy.path)

        _ = try Self.run(svnPath, ["delete", victimURL.path])
        _ = try Self.run(svnPath, ["update", "--non-interactive", workingCopy.path])
    }

    @MainActor
    func makeStore() -> ProjectStore {
        ProjectStore(
            client: client,
            credentialStore: StubCredentialStore(),
            persistence: MemoryProjectPersistence(projects: [project]),
            projectAccessManager: StubProjectAccessManager(),
            conflictFileService: ConflictFileService(
                backupRootURL: root.appendingPathComponent("backups", isDirectory: true)
            ),
            workingCopyFileService: WorkingCopyFileService(),
            workspaceOpener: StubWorkspaceOpener(),
            projectPathChecker: StubProjectPathChecker(),
            volumeNormalizationProbe: StubVolumeNormalizationProbe(),
            settingsDefaults: UserDefaults(suiteName: "tree-conflict-store-\(UUID().uuidString)")!,
            hideTemporaryFiles: true,
            updateBadgeRefreshInterval: nil
        )
    }

    @MainActor
    func snapshotMarksVictimConflicted() async throws -> Bool {
        let snapshot = try await client.workingCopySnapshot(at: workingCopy.path)
        let identity = SVNPathIdentity(rawPath: victimPath)
        return snapshot.statuses.contains { entry in
            entry.item == .conflicted && SVNPathIdentity(rawPath: entry.path) == identity
        }
    }

    func hasConflictedVictim() throws -> Bool {
        let status = try Self.run(svnPath, ["status", "--xml", workingCopy.path])
        return status.contains("tree-conflicted=\"true\"")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "RealSVNTreeConflictFixture",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return output
    }
}
