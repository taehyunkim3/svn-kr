import Foundation
import SVNCore

/// 앱 심사와 소개 이미지 촬영에 사용하는 샘플 데이터입니다.
/// 앱의 샘플 프로젝트 버튼 또는 `SVN_MAC_DEMO_MODE=1`로 진입하며,
/// 실제 프로젝트 목록, Keychain, 로컬 폴더와 SVN 서버에는 접근하지 않습니다.
@MainActor
extension ProjectStore {
    static func demo() -> ProjectStore {
        let projects = DemoData.projects
        let store = ProjectStore(
            client: DemoSVNClient(),
            credentialStore: DemoCredentialStore(),
            persistence: DemoProjectPersistence(projects: projects),
            projectAccessManager: DemoProjectAccessManager(),
            workingCopyFileService: DemoWorkingCopyFileService(),
            workspaceOpener: DemoWorkspaceOpener(),
            projectPathChecker: DemoProjectPathChecker(),
            isDemoMode: true
        )

        store.statuses = DemoData.statuses
        store.ignoredStatuses = [SVNStatusEntry(path: ".build/", item: .ignored)]
        store.workingCopyFileTree = DemoData.fileTree
        store.remoteChanges = DemoData.remoteChanges
        store.logs = DemoData.logs
        store.workingCopyRevision = SVNWorkingCopyRevision(minimum: "1842", maximum: "1842")
        store.workingCopyRepositoryPath = "/products/atlas-mobile/trunk"
        store.isWorkingCopyOutOfDate = true
        store.selectedPaths = Set(DemoData.statuses.prefix(3).map(\.path))
        store.selectedStatusPath = DemoData.statuses.first?.path
        store.diffContent = .text(DemoData.diff)
        store.projectSummaries = [
            projects[0].id: ProjectStatusSummary(localChangeCount: 6, conflictCount: 0, lockCount: 1, needsUpdate: true),
            projects[1].id: ProjectStatusSummary(localChangeCount: 2, conflictCount: 0, lockCount: 0, needsUpdate: false)
        ]
        return store
    }
}

private struct DemoProjectPathChecker: ProjectPathChecking {
    func directoryExists(at path: String) -> Bool { true }
}

private enum DemoData {
    static let atlasID = UUID(uuidString: "A7100000-0000-0000-0000-000000000001")!
    static let designSystemID = UUID(uuidString: "A7100000-0000-0000-0000-000000000002")!

    static let projects = [
        SVNProject(id: atlasID, name: "Atlas Mobile", path: "/Users/demo/Projects/Atlas-Mobile", username: "dev.kim"),
        SVNProject(id: designSystemID, name: "Shared Design System", path: "/Users/demo/Projects/Shared-Design-System", username: "design.team")
    ]

    static let statuses = [
        SVNStatusEntry(path: "Sources/Features/Login/LoginView.swift", item: .modified, revision: "1842"),
        SVNStatusEntry(path: "Sources/Features/Login/BiometricButton.swift", item: .added),
        SVNStatusEntry(path: "Resources/Colors.xcassets/AccentColor.colorset/Contents.json", item: .modified, revision: "1842"),
        SVNStatusEntry(path: "Docs/legacy-login-flow.md", item: .deleted, revision: "1817"),
        SVNStatusEntry(path: "Docs/obsolete-guide.md", item: .missing, revision: "1842", nodeKind: .file),
        SVNStatusEntry(path: "Resources/Legacy", item: .missing, revision: "1842", nodeKind: .directory)
    ]

    static let remoteChanges = [
        SVNStatusEntry(path: "Sources/App/AppCoordinator.swift", item: .modified, revision: "1845"),
        SVNStatusEntry(path: "Tests/LoginFlowTests.swift", item: .added, revision: "1845")
    ]

    static let logs = [
        SVNLogEntry(
            revision: "1845",
            author: "lee.seoyeon",
            date: Date(timeIntervalSince1970: 1_768_173_600),
            message: "로그인 화면 접근성 개선",
            changedPaths: [
                SVNChangedPath(path: "/products/atlas-mobile/trunk/Sources/Features/Login/LoginView.swift", action: .modified, kind: .file),
                SVNChangedPath(path: "/products/atlas-mobile/trunk/Tests/LoginFlowTests.swift", action: .added, kind: .file)
            ]
        ),
        SVNLogEntry(
            revision: "1844",
            author: "park.junho",
            date: Date(timeIntervalSince1970: 1_768_087_800),
            message: "다크 모드 색상 토큰 정리",
            changedPaths: [
                SVNChangedPath(path: "/products/atlas-mobile/trunk/Resources/Colors.xcassets", action: .modified, kind: .directory)
            ]
        ),
        SVNLogEntry(
            revision: "1843",
            author: "kim.minjun",
            date: Date(timeIntervalSince1970: 1_768_001_400),
            message: "생체 인증 버튼 컴포넌트 추가",
            changedPaths: [
                SVNChangedPath(path: "/products/atlas-mobile/trunk/Sources/Features/Login/BiometricButton.swift", action: .added, kind: .file)
            ]
        )
    ]

    static let fileTree = [
        WorkingCopyFileNode(
            name: "Sources", relativePath: "Sources", isDirectory: true, isSymbolicLink: false,
            svnEntry: SVNWorkingCopyEntry(path: "Sources", status: "normal", revision: "1842"),
            children: [
                WorkingCopyFileNode(
                    name: "Features", relativePath: "Sources/Features", isDirectory: true, isSymbolicLink: false,
                    svnEntry: SVNWorkingCopyEntry(path: "Sources/Features", status: "normal", revision: "1842"),
                    children: [
                        WorkingCopyFileNode(name: "LoginView.swift", relativePath: "Sources/Features/LoginView.swift", isDirectory: false, isSymbolicLink: false, svnEntry: SVNWorkingCopyEntry(path: "Sources/Features/LoginView.swift", status: "modified", revision: "1842"), children: nil),
                        WorkingCopyFileNode(name: "BiometricButton.swift", relativePath: "Sources/Features/BiometricButton.swift", isDirectory: false, isSymbolicLink: false, svnEntry: SVNWorkingCopyEntry(path: "Sources/Features/BiometricButton.swift", status: "added", revision: nil), children: nil)
                    ]
                )
            ]
        ),
        WorkingCopyFileNode(name: "README.md", relativePath: "README.md", isDirectory: false, isSymbolicLink: false, svnEntry: SVNWorkingCopyEntry(path: "README.md", status: "normal", revision: "1842"), children: nil)
    ]

    static let diff = """
    Index: Sources/Features/Login/LoginView.swift
    ===================================================================
    --- Sources/Features/Login/LoginView.swift  (revision 1842)
    +++ Sources/Features/Login/LoginView.swift  (working copy)
    @@ -28,6 +28,12 @@
         PrimaryButton(title: \"로그인\") {
             viewModel.signIn()
         }
    +
    +    BiometricButton(
    +        title: \"Face ID로 계속하기\",
    +        action: viewModel.signInWithBiometrics
    +    )
     }
    """
}

private struct DemoProjectPersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private struct DemoCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private final class DemoProjectAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

@MainActor
private struct DemoWorkspaceOpener: WorkspaceOpening {
    func open(_: URL) -> Bool { false }
}

private struct DemoWorkingCopyFileService: WorkingCopyFileListing {
    func tree(at _: String, svnEntries _: [SVNWorkingCopyEntry]) async throws -> [WorkingCopyFileNode] { DemoData.fileTree }
}

private actor DemoSVNClient: SVNClientServing {
    private var scheduledDeletionPaths: Set<String> = []

    func checkout(repositoryURL _: String, destinationPath _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> String { "Demo checkout complete" }
    func validateWorkingCopy(at _: String, credentials _: SVNCredentials?) async throws {}
    func verifyCredentials(at _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws {}
    func status(at _: String, credentials _: SVNCredentials?) async throws -> [SVNStatusEntry] { currentStatuses }
    func workingCopyEntries(at _: String, credentials _: SVNCredentials?) async throws -> [SVNWorkingCopyEntry] { [] }
    func workingCopySnapshot(at _: String, credentials _: SVNCredentials?) async throws -> SVNWorkingCopySnapshot {
        SVNWorkingCopySnapshot(
            statuses: currentStatuses,
            revision: SVNWorkingCopyRevision(minimum: "1842", maximum: "1842"),
            collisions: [],
            versionedPathsByCanonicalKey: [:]
        )
    }
    func repairCanonicalAliases(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopySnapshot {
        try await workingCopySnapshot(at: path, credentials: credentials)
    }
    func recoveryPreview(at _: String, credentials _: SVNCredentials?) async throws -> SVNRecoveryPreview {
        SVNRecoveryPreview(mappings: [], ignoredAliasCount: 0, blockingPaths: [])
    }
    func recoverWorkingCopy(from _: String, to destinationPath: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> SVNRecoveryResult {
        SVNRecoveryResult(
            destinationPath: destinationPath,
            snapshot: try await workingCopySnapshot(at: destinationPath, credentials: nil),
            migratedPaths: []
        )
    }
    func ignoredStatus(at _: String, credentials _: SVNCredentials?) async throws -> [SVNStatusEntry] { [SVNStatusEntry(path: ".build/", item: .ignored)] }
    func ignoreRules(at _: String, credentials _: SVNCredentials?) async throws -> [SVNIgnoreRule] { [SVNIgnoreRule(directory: ".", pattern: ".build")] }
    func addIgnoreRule(at _: String, directory _: String, pattern _: String, propertyKind _: SVNIgnorePropertyKind, credentials _: SVNCredentials?) async throws {}
    func removeIgnoreRule(at _: String, directory _: String, pattern _: String, propertyKind _: SVNIgnorePropertyKind, credentials _: SVNCredentials?) async throws {}
    func scheduleDeletion(at _: String, paths: [String], credentials _: SVNCredentials?) async throws -> SVNDeletionResult {
        scheduledDeletionPaths.formUnion(paths)
        return SVNDeletionResult(scheduledPaths: paths, failedPaths: [])
    }
    func repositoryLocks(at _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> [SVNLockInfo] { [SVNLockInfo(path: "Design/AppFlow.fig", owner: "design.team", comment: "홈 화면 개편 작업 중")] }
    func lockInfo(at _: String, relativePath _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> SVNLockInfo? { nil }
    func lock(at _: String, relativePath _: String, comment _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> String { "Locked" }
    func unlock(at _: String, relativePath _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> String { "Unlocked" }
    func conflictDetails(at _: String, relativePath _: String, credentials _: SVNCredentials?) async throws -> SVNConflictDetails? { nil }
    func resolveConflict(at _: String, relativePath _: String, choice _: SVNConflictChoice, credentials _: SVNCredentials?) async throws -> String { "Resolved" }
    func log(at _: String, limit _: Int, endingAtRevision _: String?, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> [SVNLogEntry] { DemoData.logs }
    func revisionDiff(at _: String, revision _: String, repositoryPath _: String, workingCopyRepositoryPath _: String?, pegRevision _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> String { DemoData.diff }
    func workingCopyRevision(at _: String, credentials _: SVNCredentials?) async throws -> SVNWorkingCopyRevision {
        SVNWorkingCopyRevision(minimum: "1842", maximum: "1842")
    }
    func workingCopyRepositoryPath(at _: String, credentials _: SVNCredentials?) async throws -> String { "/products/atlas-mobile/trunk" }
    func workingCopyIsOutOfDate(at _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> Bool { true }
    func remoteChanges(at _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> [SVNStatusEntry] { DemoData.remoteChanges }
    func update(at _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> String { "Updated to revision 1845" }
    func scheduleRepositoryCleanupDeletion(at _: String, relativePath _: String, credentials _: SVNCredentials?) async throws {}
    func diff(at _: String, relativePath _: String?, credentials _: SVNCredentials?) async throws -> String { DemoData.diff }
    func revert(at _: String, relativePath _: String, credentials _: SVNCredentials?) async throws -> String { "Reverted" }
    func fileLog(at _: String, relativePath _: String, limit _: Int, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> [SVNLogEntry] { DemoData.logs }
    func commit(at _: String, paths _: [String], message _: String, credentials _: SVNCredentials?, allowUntrustedServerCertificate _: Bool) async throws -> String { "Committed revision 1846" }

    private var currentStatuses: [SVNStatusEntry] {
        DemoData.statuses.map { entry in
            guard scheduledDeletionPaths.contains(entry.path) else { return entry }
            return SVNStatusEntry(
                path: entry.path,
                item: .deleted,
                revision: entry.revision,
                nodeKind: entry.nodeKind
            )
        }
    }
}
