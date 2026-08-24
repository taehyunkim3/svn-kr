import AppKit
import Foundation
import Observation
import SVNCore

struct SVNProject: Codable, Identifiable, Hashable {
    /// 비밀번호를 제외한 프로젝트 메타데이터만 UserDefaults에 직렬화합니다.
    /// bookmarkData는 App Sandbox에서 재실행 후 폴더 접근 권한을 복원하는 값입니다.
    let id: UUID
    var name: String
    var path: String
    var username: String?
    var bookmarkData: Data?
    var allowsUntrustedServerCertificate: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        username: String? = nil,
        bookmarkData: Data? = nil,
        allowsUntrustedServerCertificate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.username = username
        self.bookmarkData = bookmarkData
        self.allowsUntrustedServerCertificate = allowsUntrustedServerCertificate
    }
}

/// diff 영역이 보여 줄 의미 상태입니다.
///
/// 화면 문구 자체를 Store에 저장하지 않고 의미만 저장해 두면, 사용자가 앱 언어를
/// 바꿨을 때 현재 상태를 새 언어로 즉시 다시 그릴 수 있습니다.
enum DiffContent: Equatable {
    case placeholder
    case unavailableForUnversioned
    case noTextDiff
    case text(String)
    case failure(String)

    func localizedText(_ language: AppLanguage) -> String {
        switch self {
        case .placeholder:
            language.localized("ui.select.a.changed.file.to.view.its.diff.409b3672")
        case .unavailableForUnversioned:
            language.localized("ui.diff.is.unavailable.until.this.file.is.added.to..402fbfa5")
        case .noTextDiff:
            language.localized("ui.no.text.diff.is.available.this.may.be.a.new.or.b.e90ec831")
        case let .text(value):
            value
        case let .failure(message):
            message
        }
    }
}

enum SVNAuthenticationAction: Equatable {
    case refreshHistory
    case update
    case commit(message: String)
}

enum RefreshErrorPolicy {
    case standalone
    case coordinated(UUID)
}

enum ProjectRequestKind: Hashable {
    case refresh
    case diff
    case fileTree
    case repositoryLocks
    case conflictPreparation
}

struct SVNAuthenticationRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let action: SVNAuthenticationAction
}

@MainActor
@Observable
final class ProjectStore {
    // MARK: - 화면에 공개하는 상태

    private var changesState = ProjectChangesStore()
    private var browserState = ProjectBrowserStore()
    private var historyState = ProjectHistoryStore()
    private var updateState = ProjectUpdateStore()
    var requiresGlobalIgnoreImportConfirmation = false
    var selectedBrowserPath: String?
    var projectSummaries: [SVNProject.ID: ProjectStatusSummary] = [:]
    private(set) var filenameNormalizationWarningProjectIDs: Set<SVNProject.ID> = []
    private(set) var activeOperations: [ProjectOperation] = []
    var isShowingAddRepository = false
    var isShowingCredentials = false
    var isShowingIgnoreRules = false
    var isShowingLocks = false
    var isShowingUpdatePreview = false
    var isShowingFileHistory = false
    var isShowingPathRecovery = false
    var pathRecoveryPreview: SVNRecoveryPreview?
    var isShowingRepositoryPathNormalization = false
    var isConfirmingRepositoryPathNormalization = false
    var repositoryPathNormalizationTargets: [SVNRepositoryPathNormalizationTarget] = []
    var selectedRepositoryPathNormalizationTargets: Set<SVNRepositoryPathNormalizationTarget> = []
    var repositoryPathNormalizationCommitMessage = ""
    var repositoryPathNormalizationResult: SVNRepositoryPathNormalizationResult?
    var repositoryPathNormalizationIssue: RepositoryPathNormalizationIssue?
    var documentOpenRequest: DocumentOpenRequest?
    var activeConflictSession: ConflictResolutionSession?
    var resolvingConflictSessionID: ConflictResolutionSession.ID?
    var resolvingConflictProjectID: SVNProject.ID?
    var revertRequest: RevertRequest?
    var deletionRequest: DeletionRequest?
    var authenticationRequest: SVNAuthenticationRequest?
    var lastCompletedCommitMessage: String?
    var notice: String?
    var errorMessage: String?
    private(set) var checkoutLog = ""
    var selectedProjectID: SVNProject.ID? {
        didSet {
            guard selectedProjectID != oldValue else { return }
            resetSelectedProjectState()
        }
    }
    var projects: [SVNProject] = [] { didSet { save() } }

    var statuses: [SVNStatusEntry] {
        get { changesState.statuses }
        set { changesState.statuses = newValue }
    }
    var pathCollisions: [SVNPathCollision] {
        get { changesState.pathCollisions }
        set { changesState.pathCollisions = newValue }
    }
    var ignoredStatuses: [SVNStatusEntry] {
        get { changesState.ignoredStatuses }
        set { changesState.ignoredStatuses = newValue }
    }
    var ignoreRules: [SVNIgnoreRule] {
        get { changesState.ignoreRules }
        set { changesState.ignoreRules = newValue }
    }
    var gitIgnoreImportItems: [IgnoreImportItem] {
        get { changesState.gitIgnoreImportItems }
        set { changesState.gitIgnoreImportItems = newValue }
    }
    var selectedGitIgnoreImportIDs: Set<IgnoreImportItem.ID> {
        get { changesState.selectedGitIgnoreImportIDs }
        set { changesState.selectedGitIgnoreImportIDs = newValue }
    }
    var hasComparedGitIgnore: Bool {
        get { changesState.hasComparedGitIgnore }
        set { changesState.hasComparedGitIgnore = newValue }
    }
    var gitIgnoreFileExists: Bool {
        get { changesState.gitIgnoreFileExists }
        set { changesState.gitIgnoreFileExists = newValue }
    }
    var gitIgnoreLastComparedAt: Date? {
        get { changesState.gitIgnoreLastComparedAt }
        set { changesState.gitIgnoreLastComparedAt = newValue }
    }
    var showsIgnoredFiles: Bool {
        get { changesState.showsIgnoredFiles }
        set { changesState.showsIgnoredFiles = newValue }
    }
    var selectedPaths: Set<String> {
        get { changesState.selectedPaths }
        set { changesState.selectedPaths = newValue }
    }
    var selectedStatusPath: String? {
        get { changesState.selectedStatusPath }
        set { changesState.selectedStatusPath = newValue }
    }
    var diffContent: DiffContent {
        get { changesState.diffContent }
        set { changesState.diffContent = newValue }
    }
    var repositoryLocks: [SVNLockInfo] {
        get { browserState.repositoryLocks }
        set { browserState.repositoryLocks = newValue }
    }
    var workingCopyFileTree: [WorkingCopyFileNode] {
        get { browserState.workingCopyFileTree }
        set { browserState.workingCopyFileTree = newValue }
    }
    var logs: [SVNLogEntry] {
        get { historyState.logs }
        set { historyState.logs = newValue }
    }
    var selectedHistoryRevision: String? {
        get { historyState.selectedHistoryRevision }
        set { historyState.selectedHistoryRevision = newValue }
    }
    var selectedHistoryPath: String? {
        get { historyState.selectedHistoryPath }
        set { historyState.selectedHistoryPath = newValue }
    }
    var historyDiffContent: DiffContent {
        get { historyState.historyDiffContent }
        set { historyState.historyDiffContent = newValue }
    }
    var hasMoreHistory: Bool {
        get { historyState.hasMoreHistory }
        set { historyState.hasMoreHistory = newValue }
    }
    var workingCopyRevision: SVNWorkingCopyRevision? {
        get { historyState.workingCopyRevision }
        set { historyState.workingCopyRevision = newValue }
    }
    var workingCopyRepositoryPath: String? {
        get { historyState.workingCopyRepositoryPath }
        set { historyState.workingCopyRepositoryPath = newValue }
    }
    var isWorkingCopyOutOfDate: Bool? {
        get { historyState.isWorkingCopyOutOfDate }
        set { historyState.isWorkingCopyOutOfDate = newValue }
    }
    var incomingUpdateCommitBadgeText: String? {
        guard isWorkingCopyOutOfDate == true,
              let workingCopyRevision,
              let localRevision = Int(workingCopyRevision.maximum) else {
            return nil
        }

        let loadedRevisions = logs.compactMap { Int($0.revision) }
        let loadedIncomingCount = loadedRevisions.count { $0 > localRevision }
        let unloadedIncomingHistoryExists =
            hasMoreHistory && loadedRevisions.min().map { $0 > localRevision } == true
        let needsLowerBoundIndicator =
            workingCopyRevision.isMixed || unloadedIncomingHistoryExists || loadedIncomingCount == 0
        let displayedCount = max(loadedIncomingCount, 1)
        return "\(displayedCount)\(needsLowerBoundIndicator ? "+" : "")"
    }
    var fileHistory: [SVNLogEntry] {
        get { historyState.fileHistory }
        set { historyState.fileHistory = newValue }
    }
    var fileHistoryPath: String? {
        get { historyState.fileHistoryPath }
        set { historyState.fileHistoryPath = newValue }
    }
    var remoteChanges: [SVNStatusEntry] {
        get { updateState.remoteChanges }
        set { updateState.remoteChanges = newValue }
    }

    /// 소개 이미지 촬영용 실행에서는 실제 UserDefaults, Keychain, 파일 시스템과 SVN을 사용하지 않습니다.
    let isDemoMode: Bool

    // MARK: - 외부 서비스와 비동기 작업 추적

    let client: any SVNClientServing
    let credentialStore: any CredentialStoring
    private let persistence: any ProjectPersisting
    let projectAccessManager: any ProjectAccessManaging
    let workingCopyFileService: any WorkingCopyFileListing
    let conflictFileService: ConflictFileService
    private let workspaceOpener: any WorkspaceOpening
    private let projectPathChecker: any ProjectPathChecking
    private let volumeNormalizationProbe: any VolumeNormalizationProbing
    var sessionPasswords: [SVNProject.ID: String] = [:]
    var pathRecoverySourceProjectID: SVNProject.ID?
    var repositoryPathNormalizationSourceProjectID: SVNProject.ID?
    private var unavailableProjectID: SVNProject.ID?
    /// 요청 종류별 최신 토큰만 보존해 늦게 끝난 비동기 결과를 공통 규칙으로 폐기합니다.
    private var latestRequestIDs: [ProjectRequestKind: UUID] = [:]
    private var failedRefreshCycleIDs: Set<UUID> = []
    private var automaticRefreshBlockedProjectID: SVNProject.ID?
    private var filenameNormalizationProbeTasks: [SVNProject.ID: Task<Void, Never>] = [:]
    private var checkoutLogSessionID = UUID()
    /// 실행 중인 체크아웃을 취소하려면 화면이 만든 Task를 계속 붙잡고 있어야 합니다.
    /// 시트만 닫으면 Task가 살아남아 svn 프로세스가 백그라운드에서 계속 돌기 때문입니다.
    private var checkoutTask: Task<Bool, Never>?

    var selectedProject: SVNProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var isWorking: Bool { !activeOperations.isEmpty }

    var isResolvingConflict: Bool {
        resolvingConflictSessionID != nil && resolvingConflictProjectID != nil
    }

    var isHistoryLoading: Bool {
        guard let projectID = selectedProjectID else { return false }
        return activeOperations.contains { operation in
            operation.kind == .refresh(projectID) || operation.kind == .refreshHistory(projectID)
        }
    }

    var isCommittingSelectedProject: Bool {
        guard let projectID = selectedProjectID else { return false }
        return activeOperations.contains { $0.kind == .commit(projectID) }
    }

    var isLoadingSelectedProjectLocks: Bool {
        operationIsActive { .lock($0) }
    }

    var isCheckingOut: Bool {
        activeOperations.contains { $0.kind == .checkout }
    }

    var isLoadingMoreHistory: Bool {
        operationIsActive { .loadMoreHistory($0) }
    }

    var isIgnoringSelectedProject: Bool {
        operationIsActive { .ignore($0) }
    }

    var isDeletingSelectedProject: Bool {
        operationIsActive { .delete($0) }
    }

    var isRevertingSelectedProject: Bool {
        operationIsActive { .revert($0) }
    }

    var isRecoveringSelectedProject: Bool {
        operationIsActive { .recover($0) }
    }

    var isScanningRepositoryPaths: Bool {
        operationIsActive { .scanRepositoryPaths($0) }
    }

    var isNormalizingRepositoryPaths: Bool {
        operationIsActive { .normalizeRepositoryPaths($0) }
    }

    var isRepositoryPathNormalizationRunning: Bool {
        isScanningRepositoryPaths || isNormalizingRepositoryPaths
    }

    var isRelocatingProject: Bool {
        activeOperations.contains { operation in
            if case .relocate = operation.kind { return true }
            return false
        }
    }

    var isVerifyingCredentials: Bool {
        activeOperations.contains { operation in
            if case .verifyCredentials = operation.kind { return true }
            return false
        }
    }

    var isLoadingSelectedFileHistory: Bool {
        operationIsActive { .fileHistory($0) }
    }

    var isPreviewingSelectedProjectUpdate: Bool {
        operationIsActive { .previewUpdate($0) }
    }

    var isUpdatingSelectedProject: Bool {
        operationIsActive { .update($0) }
    }

    var isRefreshingSelectedProject: Bool {
        guard let projectID = selectedProjectID else { return false }
        return activeOperations.contains { operation in
            switch operation.kind {
            case .refresh(let operationProjectID),
                 .refreshLocal(let operationProjectID),
                 .refreshHistory(let operationProjectID):
                operationProjectID == projectID
            default:
                false
            }
        }
    }

    /// 선택 프로젝트의 작업 복사본 또는 저장소 상태를 바꾸는 작업만 추적합니다.
    /// 파일 기록·diff·탐색처럼 읽기 전용인 작업은 다른 액션을 불필요하게 막지 않습니다.
    var isMutatingSelectedProject: Bool {
        guard let projectID = selectedProjectID else { return false }
        return activeOperations.contains { operation in
            switch operation.kind {
            case .ignore(let operationProjectID),
                 .delete(let operationProjectID),
                 .lock(let operationProjectID),
                 .resolveConflict(let operationProjectID),
                 .revert(let operationProjectID),
                 .update(let operationProjectID),
                 .commit(let operationProjectID),
                 .recover(let operationProjectID),
                 .normalizeRepositoryPaths(let operationProjectID):
                operationProjectID == projectID
            default:
                false
            }
        }
    }

    var isSelectedProjectActionBlocked: Bool {
        isRefreshingSelectedProject
            || isMutatingSelectedProject
            || isScanningRepositoryPaths
    }

    var isPathRecoveryRunning: Bool {
        guard let projectID = pathRecoverySourceProjectID else { return false }
        return activeOperations.contains { $0.kind == .recover(projectID) }
    }

    var showsGlobalProgress: Bool {
        isWorking && !isCommittingSelectedProject
    }

    private func operationIsActive(
        _ kind: (SVNProject.ID) -> ProjectOperation.Kind
    ) -> Bool {
        guard let projectID = selectedProjectID else { return false }
        return activeOperations.contains { $0.kind == kind(projectID) }
    }

    var hasContextualErrorPresentationOwner: Bool {
        isShowingAddRepository
            || isShowingCredentials
            || isShowingUpdatePreview
            || isShowingLocks
            || authenticationRequest != nil
            || isShowingIgnoreRules
            || isShowingFileHistory
            || isShowingPathRecovery
            || isShowingRepositoryPathNormalization
            || activeConflictSession != nil
            || deletionRequest != nil
            || revertRequest != nil
            || documentOpenRequest != nil
    }

    var selectableStatusPaths: Set<String> {
        Set(statuses.lazy.filter(\.isSelectableForCommit).map(\.path))
    }

    var selectAllStatusPaths: Set<String> {
        Set(statuses.lazy.filter { $0.isSelectableForCommit && !$0.isTemporaryFile }.map(\.path))
    }

    var canRepairCanonicalAliases: Bool {
        !pathCollisions.isEmpty && pathCollisions.allSatisfy { $0.repairableRawPath != nil }
    }

    var hasUnrepairablePathCollisions: Bool {
        pathCollisions.contains { $0.repairableRawPath == nil }
    }

    var canCommitSelectedPaths: Bool {
        !hasUnrepairablePathCollisions
            && !selectedPaths.isEmpty
            && selectedPaths.isSubset(of: selectableStatusPaths)
    }

    init(
        client: any SVNClientServing = SVNClient(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        persistence: any ProjectPersisting = UserDefaultsProjectPersistence(),
        projectAccessManager: any ProjectAccessManaging = SecurityScopedProjectAccessManager(),
        conflictFileService: ConflictFileService = ConflictFileService(),
        workingCopyFileService: any WorkingCopyFileListing = WorkingCopyFileService(),
        workspaceOpener: any WorkspaceOpening = AppWorkspaceOpener(),
        projectPathChecker: any ProjectPathChecking = FileManagerProjectPathChecker(),
        volumeNormalizationProbe: any VolumeNormalizationProbing = CoreVolumeNormalizationProbe(),
        isDemoMode: Bool = false
    ) {
        self.isDemoMode = isDemoMode
        self.client = client
        self.credentialStore = credentialStore
        self.persistence = persistence
        self.projectAccessManager = projectAccessManager
        self.conflictFileService = conflictFileService
        self.workingCopyFileService = workingCopyFileService
        self.workspaceOpener = workspaceOpener
        self.projectPathChecker = projectPathChecker
        self.volumeNormalizationProbe = volumeNormalizationProbe

        var saved = persistence.loadProjects()
        projectAccessManager.restoreAccess(for: &saved)
        projects = saved
        selectedProjectID = saved.first?.id
        for project in saved { probeFilenameNormalization(for: project) }
    }

    // MARK: - 프로젝트 등록과 삭제

    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.current.localized("ui.choose.svn.local.working.folders.6d104bc9")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addProject(url) }
    }

    /// 체크아웃을 취소 가능한 Task로 감싸 실행합니다.
    /// 화면은 이 함수만 호출하고, 취소는 `cancelCheckout`으로 요청합니다.
    func startCheckout(
        repositoryURL: String,
        destinationURL: URL?,
        username: String,
        password: String,
        allowsUntrustedServerCertificate: Bool
    ) async -> Bool {
        checkoutTask?.cancel()
        let task = Task { [weak self] in
            await self?.checkout(
                repositoryURL: repositoryURL,
                destinationURL: destinationURL,
                username: username,
                password: password,
                allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
            ) ?? false
        }
        checkoutTask = task
        let didComplete = await task.value
        if checkoutTask == task { checkoutTask = nil }
        return didComplete
    }

    /// 진행 중인 체크아웃을 실제로 중단합니다. Task 취소가 `SVNClient`의
    /// 취소 처리기까지 전달되어 실행 중인 svn 프로세스를 종료시킵니다.
    func cancelCheckout() {
        guard let checkoutTask else { return }
        checkoutTask.cancel()
        self.checkoutTask = nil
    }

    func checkout(
        repositoryURL: String,
        destinationURL: URL?,
        username: String,
        password: String,
        allowsUntrustedServerCertificate: Bool
    ) async -> Bool {
        let checkoutLogSessionID = UUID()
        self.checkoutLogSessionID = checkoutLogSessionID
        checkoutLog = ""
        let repositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryURL.isEmpty, let destinationURL else {
            errorMessage = AppLanguage.current.localized("ui.choose.a.local.folder.for.the.checkout.de1fb4ce")
            return false
        }
        let destination = destinationURL.standardizedFileURL
        let destinationPath = destination.path
        guard !projects.contains(where: { $0.path == destinationPath }) else {
            errorMessage = AppLanguage.current.localized("ui.this.local.working.folder.is.already.registered.b8836f70")
            return false
        }

        errorMessage = nil
        let operationID = beginOperation(.checkout)
        defer { endOperation(operationID) }

        // 체크아웃은 파일 시스템을 실제로 변경합니다. 체크아웃 성공 이후의
        // Keychain 저장 실패까지 전체 실패로 취급하면, 화면에는 실패라고 나오지만
        // 디스크에는 파일이 남는 모호한 상태가 됩니다. 그래서 경계를 둘로 나눕니다.
        let id = UUID()
        let bookmarkData: Data
        let checkoutNotice: String
        let progressBuffer = CheckoutProgressBuffer()
        do {
            bookmarkData = try projectAccessManager.makeBookmark(for: destination)
            projectAccessManager.beginAccessing(destination, for: id)
            let credentials = username.isEmpty ? nil : SVNCredentials(username: username, password: password.isEmpty ? nil : password)
            checkoutNotice = try await client.checkout(
                repositoryURL: repositoryURL,
                destinationPath: destinationPath,
                credentials: credentials,
                allowUntrustedServerCertificate: allowsUntrustedServerCertificate,
                progress: { [weak self] output in
                    let accumulatedOutput = progressBuffer.append(output)
                    Task { @MainActor [weak self] in
                        guard self?.checkoutLogSessionID == checkoutLogSessionID,
                              accumulatedOutput.utf8.count >= (self?.checkoutLog.utf8.count ?? 0) else { return }
                        self?.checkoutLog = accumulatedOutput
                    }
                }
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            checkoutLog = progressBuffer.output
        } catch {
            checkoutLog = progressBuffer.output
            projectAccessManager.endAccessing(url: destinationURL.standardizedFileURL)
            // 사용자가 직접 멈춘 작업은 실패가 아니므로 오류 대화상자를 띄우지 않습니다.
            // 다만 이미 내려받은 파일은 디스크에 남으므로 대상 폴더를 함께 알립니다.
            if error is CancellationError || Task.isCancelled {
                errorMessage = nil
                notice = AppLanguage.current.localized(
                    "ui.the.checkout.was.canceled.partially.downloaded.f.7a1c4d58",
                    destinationPath
                )
                return false
            }
            errorMessage = localizedError(error)
            return false
        }

        let project = SVNProject(
            id: id,
            name: destination.lastPathComponent,
            path: destination.path,
            username: username.isEmpty ? nil : username,
            bookmarkData: bookmarkData,
            allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
        )
        projects.append(project)
        selectedProjectID = project.id
        probeFilenameNormalization(for: project)
        notice = checkoutNotice

        var keychainWarning: String?
        if !password.isEmpty {
            // Keychain 저장이 실패해도 이번 실행의 인증과 체크아웃 결과는 유지합니다.
            sessionPasswords[id] = password
            do {
                try credentialStore.setPassword(password, for: id)
            } catch {
                keychainWarning = AppLanguage.current.localized("ui.checkout.completed.but.the.password.could.not.be.ed5274e5", localizedError(error))
            }
        }

        await refresh()
        // refresh의 완료 안내보다 자격 증명 보존 실패가 더 중요한 정보이므로
        // 마지막에 다시 적용해 사용자가 다음 실행에 대비할 수 있게 합니다.
        if let keychainWarning { notice = keychainWarning }
        return true
    }

    func addProject(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !projects.contains(where: { $0.path == path }) else { return }
        Task {
            let operationID = beginOperation(.registerProject)
            defer { endOperation(operationID) }
            let projectID = UUID()
            do {
                let bookmarkData = try projectAccessManager.makeBookmark(for: url)
                projectAccessManager.beginAccessing(url, for: projectID)
                try await client.validateWorkingCopy(at: path, credentials: nil)
                let project = SVNProject(id: projectID, name: url.lastPathComponent, path: path, bookmarkData: bookmarkData)
                projects.append(project)
                selectedProjectID = project.id
                probeFilenameNormalization(for: project)
                await refresh()
            } catch {
                projectAccessManager.endAccessing(projectID: projectID)
                errorMessage = localizedError(error)
            }
        }
    }

    /// 이미 등록한 프로젝트의 로컬 폴더 위치를 바꿉니다.
    ///
    /// Finder에서 작업 폴더를 옮겼을 때 프로젝트를 지우고 다시 추가하면 Keychain
    /// 비밀번호와 프로젝트 식별자가 함께 사라집니다. 같은 식별자를 유지한 채
    /// 경로와 보안 범위 bookmark만 교체해 자격 증명을 보존합니다.
    func relocateProject(_ projectID: SVNProject.ID, to destinationURL: URL) async -> Bool {
        guard let currentIndex = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        let destination = destinationURL.standardizedFileURL
        let destinationPath = destination.path
        let previousPath = projects[currentIndex].path
        guard destinationPath != previousPath else { return true }
        guard !projects.contains(where: { $0.id != projectID && $0.path == destinationPath }) else {
            errorMessage = AppLanguage.current.localized("ui.this.local.working.folder.is.already.registered.b8836f70")
            return false
        }

        errorMessage = nil
        let operationID = beginOperation(.relocate(projectID))
        defer { endOperation(operationID) }

        let previousURL = URL(fileURLWithPath: previousPath, isDirectory: true)
        do {
            let bookmarkData = try projectAccessManager.makeBookmark(for: destination)
            // 한 프로젝트는 한 폴더에만 접근 권한을 가지므로 새 폴더를 열기 전에
            // 이전 폴더 권한을 먼저 반납합니다.
            projectAccessManager.endAccessing(projectID: projectID)
            projectAccessManager.beginAccessing(destination, for: projectID)
            try await client.validateWorkingCopy(at: destinationPath, credentials: nil)
            guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
            projects[index].path = destinationPath
            projects[index].name = destination.lastPathComponent
            projects[index].bookmarkData = bookmarkData
            probeFilenameNormalization(for: projects[index])
            notice = AppLanguage.current.localized(
                "ui.the.working.folder.was.changed.to.9c6f01b2",
                destinationPath
            )
            if selectedProjectID == projectID { await refresh() }
            return true
        } catch {
            // 검증에 실패하면 등록 정보를 바꾸지 않고 이전 폴더 접근 권한을 복구합니다.
            projectAccessManager.endAccessing(projectID: projectID)
            projectAccessManager.beginAccessing(previousURL, for: projectID)
            errorMessage = localizedError(error)
            return false
        }
    }

    func removeProject(_ projectID: SVNProject.ID) {
        sessionPasswords[projectID] = nil
        try? credentialStore.deletePassword(for: projectID)
        projectAccessManager.endAccessing(projectID: projectID)
        projectSummaries[projectID] = nil
        filenameNormalizationWarningProjectIDs.remove(projectID)
        filenameNormalizationProbeTasks.removeValue(forKey: projectID)?.cancel()
        projects.removeAll { $0.id == projectID }
        if selectedProjectID == projectID {
            selectedProjectID = projects.first?.id
        }
    }

    private func probeFilenameNormalization(for project: SVNProject) {
        filenameNormalizationProbeTasks.removeValue(forKey: project.id)?.cancel()
        filenameNormalizationWarningProjectIDs.remove(project.id)
        let probe = volumeNormalizationProbe
        let projectID = project.id
        let projectPath = project.path
        filenameNormalizationProbeTasks[projectID] = Task { [weak self] in
            let result = await probe.preservesPrecomposedFilenames(at: projectPath)
            guard !Task.isCancelled else { return }
            self?.applyFilenameNormalizationResult(result, projectID: projectID, path: projectPath)
        }
    }

    private func applyFilenameNormalizationResult(
        _ result: Bool?,
        projectID: SVNProject.ID,
        path: String
    ) {
        guard projects.contains(where: { $0.id == projectID && $0.path == path }) else { return }
        if result == false {
            filenameNormalizationWarningProjectIDs.insert(projectID)
        } else {
            filenameNormalizationWarningProjectIDs.remove(projectID)
        }
    }

    func waitForFilenameNormalizationProbes() async {
        for task in filenameNormalizationProbeTasks.values {
            await task.value
        }
    }

    // MARK: - SVN 작업

    func refreshSelectedProject(manual: Bool) async {
        guard !isDemoMode, let project = selectedProject else { return }
        if manual {
            automaticRefreshBlockedProjectID = nil
            unavailableProjectID = nil
        } else if !automaticRefreshCanRun(for: project) {
            return
        }
        guard ensureWorkingCopyDirectoryExists(for: project) else { return }

        let cycleID = UUID()
        let errorPolicy = RefreshErrorPolicy.coordinated(cycleID)
        async let projectRefresh: Void = refresh(errorPolicy: errorPolicy)
        async let browserRefresh: Void = refreshWorkingCopyBrowser(errorPolicy: errorPolicy)
        _ = await (projectRefresh, browserRefresh)
        finishRefreshCycle(cycleID)
    }

    func refreshLocalWorkingCopy(errorPolicy: RefreshErrorPolicy = .standalone) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return }
        let requestID = registerRefreshRequest()
        let operationID = beginOperation(.refreshLocal(project.id))
        defer { endOperation(operationID) }
        _ = await applyLocalWorkingCopyRefresh(
            for: project,
            requestID: requestID,
            errorPolicy: errorPolicy
        )
    }

    func refresh(errorPolicy: RefreshErrorPolicy = .standalone) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return }
        let requestID = prepareRefreshRequest()
        let operationID = beginOperation(.refresh(project.id))
        defer { endOperation(operationID) }

        guard await applyLocalWorkingCopyRefresh(
            for: project,
            requestID: requestID,
            errorPolicy: errorPolicy
        ) else { return }

        do {
            let projectCredentials = try credentials(for: project)
            async let newLogs = client.log(
                at: project.path,
                limit: 50,
                endingAtRevision: nil,
                credentials: projectCredentials,
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            async let outOfDate = client.workingCopyIsOutOfDate(
                at: project.path,
                credentials: projectCredentials,
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            let (logs, isWorkingCopyOutOfDate) = try await (newLogs, outOfDate)
            guard canApplyRefresh(requestID, projectID: project.id) else { return }
            self.logs = logs
            self.hasMoreHistory = logs.count == 50
            self.isWorkingCopyOutOfDate = isWorkingCopyOutOfDate
            updateRemoteSummary(for: project.id, needsUpdate: isWorkingCopyOutOfDate)
            notice = AppLanguage.current.localized("ui.refreshed.41ebae4b", project.name)
        } catch {
            if canApplyRefresh(requestID, projectID: project.id) {
                handleRemoteError(
                    error,
                    project: project,
                    action: .refreshHistory,
                    refreshErrorPolicy: errorPolicy
                )
            }
        }
    }

    private func prepareRefreshRequest() -> UUID {
        let requestID = registerRefreshRequest()
        isWorkingCopyOutOfDate = nil
        isShowingPathRecovery = false
        pathRecoveryPreview = nil
        pathRecoverySourceProjectID = nil
        return requestID
    }

    private func registerRefreshRequest() -> UUID {
        beginRequest(.refresh)
    }

    private func applyLocalWorkingCopyRefresh(
        for project: SVNProject,
        requestID: UUID,
        errorPolicy: RefreshErrorPolicy
    ) async -> Bool {
        do {
            async let newSnapshot = client.workingCopySnapshot(at: project.path, credentials: nil)
            async let newWorkingCopyRepositoryPath = client.workingCopyRepositoryPath(
                at: project.path,
                credentials: nil
            )
            let (snapshot, workingCopyRepositoryPath) = try await (
                newSnapshot,
                newWorkingCopyRepositoryPath
            )
            guard canApplyRefresh(requestID, projectID: project.id) else { return false }
            statuses = snapshot.statuses
            workingCopyRevision = snapshot.revision
            pathCollisions = snapshot.collisions
            self.workingCopyRepositoryPath = workingCopyRepositoryPath
            selectedPaths.formIntersection(selectableStatusPaths)
            updateLocalSummary(for: project.id, statuses: snapshot.statuses)
            notice = AppLanguage.current.localized("ui.local.changes.refreshed.617acbc6", project.name)
            return true
        } catch {
            if canApplyRefresh(requestID, projectID: project.id) {
                publishRefreshError(error, projectID: project.id, policy: errorPolicy)
            }
            return false
        }
    }

    func loadDiff(for path: String) async {
        guard let project = selectedProject else { return }
        let requestID = beginRequest(.diff)
        selectedStatusPath = path
        if statuses.first(where: { $0.path == path })?.item == .unversioned {
            diffContent = .unavailableForUnversioned
            return
        }
        do {
            let value = try await client.diff(at: project.path, relativePath: path, credentials: nil)
            guard canApplyRequest(requestID, kind: .diff, projectID: project.id),
                  selectedStatusPath == path else { return }
            diffContent = value.isEmpty ? .noTextDiff : .text(value)
        } catch {
            if canApplyRequest(requestID, kind: .diff, projectID: project.id) {
                errorMessage = localizedError(error)
            }
        }
    }

    func commit(message: String) async -> Bool {
        guard let project = selectedProject, !selectedPaths.isEmpty else { return false }
        let paths = selectedPaths.sorted()
        let missingPaths = statuses.lazy
            .filter { $0.item == .missing && self.selectedPaths.contains($0.path) }
            .map(\.path)
        guard missingPaths.isEmpty else {
            errorMessage = AppLanguage.current.localized(
                "error.choose.missing.items",
                missingPaths.joined(separator: ", ")
            )
            return false
        }
        guard !Self.containsSelectedConflict(selectedPaths: selectedPaths, statuses: statuses) else {
            errorMessage = AppLanguage.current.localized("ui.resolve.conflicted.files.before.committing.e5cfd21c")
            return false
        }
        let operationID = beginOperation(.commit(project.id))
        defer { endOperation(operationID) }
        do {
            let result = try await client.commit(
                at: project.path,
                paths: paths,
                message: message,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedProjectID == project.id else { return true }
            notice = result
            selectedPaths.subtract(paths)
            lastCompletedCommitMessage = message
            await refresh()
            return true
        } catch let SVNError.commitSucceededWithValidationWarning(_, details) {
            guard selectedProjectID == project.id else { return true }
            selectedPaths.subtract(paths)
            lastCompletedCommitMessage = message
            await refresh()
            notice = localizedError(SVNError.commitSucceededWithValidationWarning(
                output: "",
                details: details
            ))
            return true
        } catch let error as SVNError {
            if selectedProjectID == project.id {
                if case .workingCopyOutOfDate = error {
                    isWorkingCopyOutOfDate = true
                }
                handleRemoteError(error, project: project, action: .commit(message: message))
            }
            return false
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .commit(message: message))
            }
            return false
        }
    }

    static func containsSelectedConflict(
        selectedPaths: Set<String>,
        statuses: [SVNStatusEntry]
    ) -> Bool {
        let conflictedPaths = Set(statuses.lazy.filter { $0.item == .conflicted }.map(\.path))
        return !selectedPaths.isDisjoint(with: conflictedPaths)
    }

    func hasSavedPassword(for projectID: UUID) -> Bool {
        (try? credentialStore.password(for: projectID)) != nil
    }

    /// 입력한 계정으로 저장소에 접근할 수 있는지 저장 전에 확인합니다.
    ///
    /// 잘못된 계정을 먼저 저장하면 Keychain과 프로젝트 목록이 이미 바뀐 뒤에야
    /// 새로고침이 실패해 되돌릴 것이 남습니다. 확인을 저장보다 앞에 두면 실패했을 때
    /// 아무것도 바뀌지 않은 상태가 되어 사용자가 재입력과 취소를 그대로 고를 수 있습니다.
    /// 반환값은 실패 사유이고, `nil`이면 확인에 성공한 것입니다.
    func verifyCredentials(
        for projectID: SVNProject.ID,
        username: String,
        password: String,
        allowsUntrustedServerCertificate: Bool
    ) async -> String? {
        guard let project = projects.first(where: { $0.id == projectID }) else { return nil }
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // 비밀번호를 비워 두면 기존에 저장된 비밀번호를 그대로 쓰겠다는 뜻이므로
        // 확인에도 같은 값을 사용해야 화면 안내와 실제 동작이 어긋나지 않습니다.
        let effectivePassword = password.isEmpty
            ? (sessionPasswords[projectID] ?? (try? credentialStore.password(for: projectID)) ?? nil)
            : password
        let credentials = username.isEmpty
            ? nil
            : SVNCredentials(username: username, password: effectivePassword)

        let operationID = beginOperation(.verifyCredentials(projectID))
        defer { endOperation(operationID) }
        do {
            try await client.verifyCredentials(
                at: project.path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowsUntrustedServerCertificate
            )
            return nil
        } catch {
            return localizedError(error)
        }
    }

    func saveCredentials(
        for projectID: UUID,
        username: String,
        newPassword: String,
        allowsUntrustedServerCertificate: Bool
    ) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        do {
            let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            projects[index].username = username.isEmpty ? nil : username
            projects[index].allowsUntrustedServerCertificate = allowsUntrustedServerCertificate
            if !newPassword.isEmpty {
                try credentialStore.setPassword(newPassword, for: projectID)
                sessionPasswords[projectID] = newPassword
            }
            notice = AppLanguage.current.localized("ui.credentials.saved.for.409bff39", projects[index].name)
            return true
        } catch {
            errorMessage = localizedError(error)
            return false
        }
    }

    func deleteSavedPassword(for projectID: UUID) -> Bool {
        do {
            try credentialStore.deletePassword(for: projectID)
            sessionPasswords[projectID] = nil
            notice = AppLanguage.current.localized("ui.the.saved.password.was.deleted.a729310e")
            return true
        } catch {
            errorMessage = localizedError(error)
            return false
        }
    }

    func retryKeychainAccess(for request: SVNAuthenticationRequest) async {
        guard authenticationRequest?.id == request.id else { return }
        sessionPasswords[request.projectID] = nil
        authenticationRequest = nil
        await resume(request)
    }

    func useCredentials(
        for request: SVNAuthenticationRequest,
        username: String,
        password: String,
        saveInKeychain: Bool
    ) async -> Bool {
        guard authenticationRequest?.id == request.id,
              let index = projects.firstIndex(where: { $0.id == request.projectID }) else { return false }
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { return false }

        do {
            projects[index].username = username
            if saveInKeychain {
                try credentialStore.setPassword(password, for: request.projectID)
            }
            sessionPasswords[request.projectID] = password
            authenticationRequest = nil
            await resume(request)
            return true
        } catch {
            if isKeychainAccessDenied(error) {
                notice = authenticationNotice
            } else {
                errorMessage = localizedError(error)
            }
            return false
        }
    }

    func cancelAuthentication(for request: SVNAuthenticationRequest) {
        guard authenticationRequest?.id == request.id else { return }
        authenticationRequest = nil
        notice = AppLanguage.current.localized("ui.authentication.was.canceled.local.changes.remain.c4984bab")
    }

    // MARK: - 인증 조회와 실패 후 작업 재개

    func credentials(for project: SVNProject) throws -> SVNCredentials? {
        guard let username = project.username, !username.isEmpty else { return nil }
        if let password = sessionPasswords[project.id] {
            return SVNCredentials(username: username, password: password)
        }
        let password = try credentialStore.password(for: project.id)
        if let password, !password.isEmpty {
            sessionPasswords[project.id] = password
        }
        return SVNCredentials(username: username, password: password)
    }

    func handleRemoteError(
        _ error: Error,
        project: SVNProject,
        action: SVNAuthenticationAction,
        refreshErrorPolicy: RefreshErrorPolicy = .standalone
    ) {
        if isKeychainAccessDenied(error) {
            authenticationRequest = SVNAuthenticationRequest(projectID: project.id, action: action)
            notice = authenticationNotice
        } else {
            publishRefreshError(error, projectID: project.id, policy: refreshErrorPolicy)
        }
    }

    func publishRefreshError(
        _ error: Error,
        projectID: SVNProject.ID,
        policy: RefreshErrorPolicy
    ) {
        guard selectedProjectID == projectID else { return }
        switch policy {
        case .standalone:
            automaticRefreshBlockedProjectID = projectID
            errorMessage = localizedError(error)
        case let .coordinated(cycleID):
            guard failedRefreshCycleIDs.insert(cycleID).inserted else { return }
            automaticRefreshBlockedProjectID = projectID
            errorMessage = localizedError(error)
        }
    }

    func automaticRefreshCanRun(for project: SVNProject) -> Bool {
        if unavailableProjectID == project.id,
           projectPathChecker.directoryExists(at: project.path) {
            unavailableProjectID = nil
            automaticRefreshBlockedProjectID = nil
        }
        return automaticRefreshBlockedProjectID != project.id
    }

    func finishRefreshCycle(_ cycleID: UUID) {
        failedRefreshCycleIDs.remove(cycleID)
    }

    private func isKeychainAccessDenied(_ error: Error) -> Bool {
        (error as? KeychainStoreError)?.isAccessDenied == true
    }

    private var authenticationNotice: String {
        AppLanguage.current.localized("ui.keychain.access.was.denied.choose.how.to.authent.0d8d881a")
    }

    private func resume(_ request: SVNAuthenticationRequest) async {
        guard selectedProjectID == request.projectID else { return }
        switch request.action {
        case .refreshHistory:
            await refreshRemoteHistory(for: request.projectID)
        case .update:
            await update()
        case let .commit(message):
            _ = await commit(message: message)
        }
    }

    private func refreshRemoteHistory(for projectID: SVNProject.ID) async {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        let operationID = beginOperation(.refreshHistory(project.id))
        defer { endOperation(operationID) }
        do {
            let newLogs = try await client.log(
                at: project.path,
                limit: 50,
                endingAtRevision: nil,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            logs = newLogs
            hasMoreHistory = newLogs.count == 50
            notice = AppLanguage.current.localized("ui.history.refreshed.5c159ee8", project.name)
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .refreshHistory)
            }
        }
    }

    func localizedError(_ error: Error, language: AppLanguage = .current) -> String {
        if let conflictError = error as? ConflictFileError {
            return SVNErrorLocalization.message(for: conflictError, language: language)
        }
        if let svnError = error as? SVNError {
            return SVNErrorLocalization.message(for: svnError, language: language)
        }
        return error.localizedDescription
    }

    func openFile(_ relativePath: String, in project: SVNProject) {
        let url = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath)
        guard workspaceOpener.open(url) else {
            errorMessage = AppLanguage.current.localized("ui.unable.to.open.file.ae08bd77", relativePath)
            return
        }
    }

    func openWorkspaceURL(_ url: URL) {
        guard workspaceOpener.open(url) else {
            errorMessage = AppLanguage.current.localized("ui.could.not.open.the.file.263874fa")
            return
        }
    }

    private func save() {
        // 프로젝트 목록 변경마다 즉시 저장해 앱이 비정상 종료되어도 최근 등록 및
        // 삭제 상태를 최대한 보존합니다. 인코딩 실패 시 기존 저장값은 유지합니다.
        persistence.saveProjects(projects)
    }

    func updateLocalSummary(for projectID: SVNProject.ID, statuses: [SVNStatusEntry]) {
        var summary = projectSummaries[projectID] ?? ProjectStatusSummary()
        summary.localChangeCount = statuses.count
        summary.conflictCount = statuses.filter { $0.item == .conflicted }.count
        projectSummaries[projectID] = summary
    }

    func updateRemoteSummary(for projectID: SVNProject.ID, needsUpdate: Bool) {
        var summary = projectSummaries[projectID] ?? ProjectStatusSummary()
        summary.needsUpdate = needsUpdate
        projectSummaries[projectID] = summary
    }

    func updateLockSummary(for projectID: SVNProject.ID, lockCount: Int) {
        var summary = projectSummaries[projectID] ?? ProjectStatusSummary()
        summary.lockCount = lockCount
        projectSummaries[projectID] = summary
    }

    // MARK: - 화면 상태와 작업 수명 관리

    /// 프로젝트가 바뀔 때 이전 프로젝트의 화면 상태가 잠깐 보이지 않도록 관련
    /// 상태를 한곳에서 초기화합니다. 진행 중이던 요청 토큰도 폐기합니다.
    private func resetSelectedProjectState() {
        latestRequestIDs.removeAll()
        failedRefreshCycleIDs = []
        automaticRefreshBlockedProjectID = nil
        changesState = ProjectChangesStore()
        browserState = ProjectBrowserStore()
        historyState = ProjectHistoryStore()
        updateState = ProjectUpdateStore()
        requiresGlobalIgnoreImportConfirmation = false
        selectedBrowserPath = nil
        documentOpenRequest = nil
        activeConflictSession = nil
        resolvingConflictSessionID = nil
        resolvingConflictProjectID = nil
        revertRequest = nil
        deletionRequest = nil
        isShowingRepositoryPathNormalization = false
        isConfirmingRepositoryPathNormalization = false
        repositoryPathNormalizationTargets = []
        selectedRepositoryPathNormalizationTargets = []
        repositoryPathNormalizationCommitMessage = ""
        repositoryPathNormalizationResult = nil
        repositoryPathNormalizationIssue = nil
        repositoryPathNormalizationSourceProjectID = nil
        notice = nil
        errorMessage = nil
        authenticationRequest = nil
        unavailableProjectID = nil
    }

    /// Finder 등 외부에서 등록 폴더가 삭제된 경우 자동 새로고침들이 같은 오류를
    /// 연달아 표시하지 않도록 선택당 한 번만 안내합니다. 폴더가 복구되면 즉시
    /// 정상 새로고침으로 돌아갈 수 있게 누락 상태를 해제합니다.
    func ensureWorkingCopyDirectoryExists(for project: SVNProject) -> Bool {
        guard selectedProjectID == project.id else { return false }
        guard projectPathChecker.directoryExists(at: project.path) else {
            guard unavailableProjectID != project.id else { return false }
            unavailableProjectID = project.id
            automaticRefreshBlockedProjectID = project.id
            errorMessage = AppLanguage.current.localized("ui.the.working.folder.no.longer.exists.restore.the..4946d37c", project.name, project.path)
            return false
        }
        if unavailableProjectID == project.id {
            unavailableProjectID = nil
            automaticRefreshBlockedProjectID = nil
        }
        return true
    }

    @discardableResult
    func beginOperation(_ kind: ProjectOperation.Kind) -> UUID {
        let operation = ProjectOperation(kind: kind)
        activeOperations.append(operation)
        return operation.id
    }

    func endOperation(_ id: UUID) {
        activeOperations.removeAll { $0.id == id }
    }

    /// 요청을 시작했던 프로젝트가 아직 선택되어 있고, 더 최신 refresh가 없을 때만
    /// 비동기 결과를 화면 상태에 반영합니다.
    private func canApplyRefresh(_ requestID: UUID, projectID: SVNProject.ID) -> Bool {
        canApplyRequest(requestID, kind: .refresh, projectID: projectID)
    }

    @discardableResult
    func beginRequest(_ kind: ProjectRequestKind) -> UUID {
        let requestID = UUID()
        latestRequestIDs[kind] = requestID
        return requestID
    }

    func finishRequest(_ requestID: UUID, kind: ProjectRequestKind) {
        guard latestRequestIDs[kind] == requestID else { return }
        latestRequestIDs[kind] = nil
    }

    func canApplyRequest(
        _ requestID: UUID,
        kind: ProjectRequestKind,
        projectID: SVNProject.ID
    ) -> Bool {
        latestRequestIDs[kind] == requestID && selectedProjectID == projectID
    }
}

private final class CheckoutProgressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOutput = ""

    var output: String {
        lock.withLock { storedOutput }
    }

    func append(_ output: String) -> String {
        lock.withLock {
            storedOutput += output
            return storedOutput
        }
    }
}
