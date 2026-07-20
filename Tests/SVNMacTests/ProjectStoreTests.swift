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

    #expect(store.notice == AppLanguage.current.text(
        "충돌을 해결 상태로 표시했습니다. diff를 확인한 뒤 커밋하세요.",
        "The conflict is marked resolved. Review the diff before committing."
    ))
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
@Test func workingChoiceDoesNotResolveOrDiscardConflictSession() async throws {
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
    await store.resolveActiveConflict(using: .working)

    #expect(store.activeConflictSession == session)
    #expect(await client.lastConflictChoice() == nil)
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
    await resolveGate.release()
    await resolution.value

    #expect(store.selectedProjectID == otherProject.id)
    #expect(store.errorMessage == "new-project-error")
    #expect(store.notice == "new-project-notice")
    #expect(await client.snapshotRequestCount() == 0)
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
    await resolveGate.release()
    await oldResolution.value

    #expect(store.activeConflictSession?.id == newerSessionID)
    #expect(store.notice == nil)
    #expect(await client.snapshotRequestCount() == 0)
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

    await resolveGate.release()
    await oldResolution.value

    #expect(store.activeConflictSession?.id == newerSessionID)
    #expect(store.errorMessage == "newer-error")
    #expect(store.notice == "newer-notice")
    #expect(await client.snapshotRequestCount() == 0)
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
@Test func versionedDocumentOffersLockBeforeOpening() async {
    let project = SVNProject(name: "프로젝트", path: "/tmp/project")
    let opener = StubWorkspaceOpener()
    let client = StubSVNClient()
    let store = makeStore(projects: [project], client: client, workspaceOpener: opener)

    await store.prepareToOpen(path: "plan.pptx", isVersioned: true)

    #expect(opener.openedURLs.isEmpty)
    #expect(store.documentOpenRequest?.relativePath == "plan.pptx")
    #expect(await client.lockInfoRequestCount() == 1)
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
        projectAccessManager: StubProjectAccessManager()
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

@MainActor
private func makeStore(
    projects: [SVNProject],
    client: StubSVNClient = StubSVNClient(),
    fileService: any WorkingCopyFileListing = WorkingCopyFileService(),
    conflictFileService: ConflictFileService = ConflictFileService(),
    workspaceOpener: any WorkspaceOpening = StubWorkspaceOpener()
) -> ProjectStore {
    ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(projects: projects),
        projectAccessManager: StubProjectAccessManager(),
        conflictFileService: conflictFileService,
        workingCopyFileService: fileService,
        workspaceOpener: workspaceOpener
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

private enum TestError: Error {
    case credentialWriteFailed
    case backupFailed
    case resolveConflictFailed
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

private struct RevisionDiffRequest: Equatable, Sendable {
    let revision: String
    let repositoryPath: String
    let workingCopyRepositoryPath: String?
    let pegRevision: String
}

private actor StubSVNClient: SVNClientServing {
    let statusesByPath: [String: [SVNStatusEntry]]
    let revisionsByPath: [String: String]
    let delaysByPath: [String: Duration]
    let checkoutResult: String
    let lockInfoByPath: [String: SVNLockInfo]
    let snapshotsByPath: [String: SVNWorkingCopySnapshot]
    let repairedSnapshotsByPath: [String: SVNWorkingCopySnapshot]
    let recoveryPreviewValue: SVNRecoveryPreview
    let recoveryResultValue: SVNRecoveryResult
    let commitCompletedWarning: (output: String, details: String)?
    let conflictDetailsValue: SVNConflictDetails?
    let conflictDetailsByRelativePath: [String: SVNConflictDetails]
    let conflictDetailsGatesByRelativePath: [String: AsyncTestGate]
    let resolveError: Error?
    let resolveGate: AsyncTestGate?
    private var revisionDiffRequests: [RevisionDiffRequest] = []
    private var lockInfoRequests = 0
    private var recoveryPaths: [String] = []
    private var canonicalAliasRepairRequests = 0
    private var snapshotRequests = 0
    private var conflictChoices: [SVNConflictChoice] = []
    private var conflictDetailsRequestCounts: [String: Int] = [:]

    init(
        statusesByPath: [String: [SVNStatusEntry]] = [:],
        revisionsByPath: [String: String] = [:],
        delaysByPath: [String: Duration] = [:],
        checkoutResult: String = "checked out",
        lockInfoByPath: [String: SVNLockInfo] = [:],
        snapshotsByPath: [String: SVNWorkingCopySnapshot] = [:],
        repairedSnapshotsByPath: [String: SVNWorkingCopySnapshot] = [:],
        recoveryPreview: SVNRecoveryPreview = SVNRecoveryPreview(
            mappings: [], ignoredAliasCount: 0, blockingPaths: []
        ),
        recoveryResult: SVNRecoveryResult? = nil,
        commitCompletedWarning: (output: String, details: String)? = nil,
        conflictDetailsValue: SVNConflictDetails? = nil,
        conflictDetailsByRelativePath: [String: SVNConflictDetails] = [:],
        conflictDetailsGatesByRelativePath: [String: AsyncTestGate] = [:],
        resolveError: Error? = nil,
        resolveGate: AsyncTestGate? = nil
    ) {
        self.statusesByPath = statusesByPath
        self.revisionsByPath = revisionsByPath
        self.delaysByPath = delaysByPath
        self.checkoutResult = checkoutResult
        self.lockInfoByPath = lockInfoByPath
        self.snapshotsByPath = snapshotsByPath
        self.repairedSnapshotsByPath = repairedSnapshotsByPath
        self.commitCompletedWarning = commitCompletedWarning
        self.conflictDetailsValue = conflictDetailsValue
        self.conflictDetailsByRelativePath = conflictDetailsByRelativePath
        self.conflictDetailsGatesByRelativePath = conflictDetailsGatesByRelativePath
        self.resolveError = resolveError
        self.resolveGate = resolveGate
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
    func validateWorkingCopy(at path: String, credentials: SVNCredentials?) async throws {}
    func status(at path: String, credentials: SVNCredentials?) async throws -> [SVNStatusEntry] {
        await delay(for: path)
        return statusesByPath[path] ?? []
    }
    func workingCopyEntries(at path: String, credentials: SVNCredentials?) async throws -> [SVNWorkingCopyEntry] { [] }
    func workingCopySnapshot(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopySnapshot {
        snapshotRequests += 1
        await delay(for: path)
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
    func lastRecoveryPaths() -> [String] { recoveryPaths }
    func ignoredStatus(at path: String, credentials: SVNCredentials?) async throws -> [SVNStatusEntry] { [] }
    func ignoreRules(at path: String, credentials: SVNCredentials?) async throws -> [SVNIgnoreRule] { [] }
    func addIgnoreRule(at path: String, directory: String, pattern: String, credentials: SVNCredentials?) async throws {}
    func removeIgnoreRule(at path: String, directory: String, pattern: String, credentials: SVNCredentials?) async throws {}
    func repositoryLocks(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLockInfo] { [] }
    func lockInfo(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> SVNLockInfo? {
        lockInfoRequests += 1
        return lockInfoByPath[relativePath]
    }
    func lockInfoRequestCount() -> Int { lockInfoRequests }
    func lock(at path: String, relativePath: String, comment: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String { "locked" }
    func unlock(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String { "unlocked" }
    func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> SVNConflictDetails? {
        conflictDetailsRequestCounts[relativePath, default: 0] += 1
        if let gate = conflictDetailsGatesByRelativePath[relativePath] { await gate.wait() }
        await delay(for: path)
        return conflictDetailsByRelativePath[relativePath] ?? conflictDetailsValue
    }
    func resolveConflict(at path: String, relativePath: String, choice: SVNConflictChoice, credentials: SVNCredentials?) async throws -> String {
        conflictChoices.append(choice)
        if let resolveGate { await resolveGate.wait() }
        if let resolveError { throw resolveError }
        return "resolved"
    }
    func lastConflictChoice() -> SVNConflictChoice? { conflictChoices.last }
    func conflictChoiceCount() -> Int { conflictChoices.count }
    func conflictDetailsRequestCount(for path: String) -> Int { conflictDetailsRequestCounts[path, default: 0] }
    func log(at path: String, limit: Int, endingAtRevision: String?, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLogEntry] {
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
        await delay(for: path)
        return false
    }
    func remoteChanges(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNStatusEntry] { [] }
    func update(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String { "updated" }
    func diff(at path: String, relativePath: String?, credentials: SVNCredentials?) async throws -> String { "diff" }
    func revert(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> String { "reverted" }
    func fileLog(at path: String, relativePath: String, limit: Int, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLogEntry] { [] }
    func commit(at path: String, paths: [String], message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String {
        if let commitCompletedWarning {
            throw SVNError.commitSucceededWithValidationWarning(
                output: commitCompletedWarning.output,
                details: commitCompletedWarning.details
            )
        }
        return "committed"
    }
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

private final class StubProjectAccessManager: ProjectAccessManaging {
    func makeBookmark(for url: URL) throws -> Data { Data("bookmark".utf8) }
    func restoreAccess(for projects: inout [SVNProject]) {}
    func beginAccessing(_ url: URL, for projectID: SVNProject.ID) {}
    func endAccessing(projectID: SVNProject.ID) {}
    func endAccessing(url: URL) {}
}
