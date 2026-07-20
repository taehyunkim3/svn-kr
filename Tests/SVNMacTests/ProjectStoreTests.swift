import Foundation
import SVNCore
import Testing
@testable import SVNMac

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
    workspaceOpener: any WorkspaceOpening = StubWorkspaceOpener()
) -> ProjectStore {
    ProjectStore(
        client: client,
        credentialStore: StubCredentialStore(),
        persistence: MemoryProjectPersistence(projects: projects),
        projectAccessManager: StubProjectAccessManager(),
        workingCopyFileService: fileService,
        workspaceOpener: workspaceOpener
    )
}

private func makeLog(revision: String) -> SVNLogEntry {
    SVNLogEntry(revision: revision, author: "tester", date: nil, message: "test")
}

private enum TestError: Error {
    case credentialWriteFailed
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
    private var revisionDiffRequests: [RevisionDiffRequest] = []
    private var lockInfoRequests = 0
    private var recoveryPaths: [String] = []
    private var canonicalAliasRepairRequests = 0

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
        recoveryResult: SVNRecoveryResult? = nil
    ) {
        self.statusesByPath = statusesByPath
        self.revisionsByPath = revisionsByPath
        self.delaysByPath = delaysByPath
        self.checkoutResult = checkoutResult
        self.lockInfoByPath = lockInfoByPath
        self.snapshotsByPath = snapshotsByPath
        self.repairedSnapshotsByPath = repairedSnapshotsByPath
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
    func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> SVNConflictDetails? { nil }
    func resolveConflict(at path: String, relativePath: String, choice: SVNConflictChoice, credentials: SVNCredentials?) async throws -> String { "resolved" }
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
    func commit(at path: String, paths: [String], message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String { "committed" }
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
