import AppKit
import Foundation
import Observation
import SVNCore

private final class UpdateBadgePoller: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func start(
        interval: Duration,
        maximumInterval: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        operation: @escaping @Sendable () async -> Bool
    ) {
        let task = Task {
            let maximumInterval = max(interval, maximumInterval)
            var nextInterval = interval
            while !Task.isCancelled {
                do {
                    try await sleep(nextInterval)
                } catch {
                    return
                }
                if await operation() {
                    nextInterval = interval
                } else {
                    nextInterval = min(nextInterval * 2, maximumInterval)
                }
            }
        }
        lock.lock()
        self.task = task
        lock.unlock()
    }

    deinit {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

struct SVNProject: Codable, Identifiable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case username
        case bookmarkData
        case allowsUntrustedServerCertificate
        case allowedServerCertificateFailures
    }

    static let legacyAllowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [
        .unknownCertificateAuthority,
        .commonNameMismatch,
    ]

    /// 비밀번호를 제외한 프로젝트 메타데이터만 UserDefaults에 직렬화합니다.
    /// bookmarkData는 App Sandbox에서 재실행 후 폴더 접근 권한을 복원하는 값입니다.
    let id: UUID
    var name: String
    var path: String
    var username: String?
    var bookmarkData: Data?
    var allowsUntrustedServerCertificate: Bool?
    var allowedServerCertificateFailures: Set<SVNServerCertificateFailure>

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        username: String? = nil,
        bookmarkData: Data? = nil,
        allowsUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.username = username
        self.bookmarkData = bookmarkData
        self.allowsUntrustedServerCertificate = allowsUntrustedServerCertificate
        self.allowedServerCertificateFailures = allowedServerCertificateFailures
        if allowsUntrustedServerCertificate {
            self.allowedServerCertificateFailures.formUnion(
                Self.legacyAllowedServerCertificateFailures
            )
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        allowsUntrustedServerCertificate = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowsUntrustedServerCertificate
        )
        if let rawFailures = try container.decodeIfPresent(
            [String].self,
            forKey: .allowedServerCertificateFailures
        ) {
            allowedServerCertificateFailures = Set(
                rawFailures.compactMap(SVNServerCertificateFailure.init(rawValue:))
            )
        } else if allowsUntrustedServerCertificate == true {
            allowedServerCertificateFailures = Self.legacyAllowedServerCertificateFailures
        } else {
            allowedServerCertificateFailures = []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encodeIfPresent(
            allowsUntrustedServerCertificate,
            forKey: .allowsUntrustedServerCertificate
        )
        let rawFailures = SVNServerCertificateFailure.allCases
            .filter(allowedServerCertificateFailures.contains)
            .map(\.rawValue)
        try container.encode(rawFailures, forKey: .allowedServerCertificateFailures)
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
            language.localized(.ui.changes.selectChangedFileViewItsDiff)
        case .unavailableForUnversioned:
            language.localized(.ui.commit.diffUnavailableUntilFileAddedSvnItAddedAutomaticallyWhen)
        case .noTextDiff:
            language.localized(.ui.common.noTextDiffAvailableMayNewBinaryFile)
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
    case retryManually
}

enum FolderSettingsSaveResult: Equatable {
    case saved
    case credentialFailure(String)
    case failed
}

enum RefreshErrorPolicy {
    case standalone
    case coordinated(UUID)
}

enum ProjectRequestKind: Hashable {
    case refresh
    case updateBadge(SVNProject.ID)
    case updatePreview
    case diff
    case fileHistory
    case revert
    case fileTree
    case repositoryLocks
    case conflictPreparation
}

struct SVNAuthenticationRequest: Identifiable, Equatable {
    let id: UUID
    let projectID: SVNProject.ID
    let action: SVNAuthenticationAction
    let serverCertificateTrust: ServerCertificateTrust?

    init(
        id: UUID = UUID(),
        projectID: SVNProject.ID,
        action: SVNAuthenticationAction,
        serverCertificateTrust: ServerCertificateTrust? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.action = action
        self.serverCertificateTrust = serverCertificateTrust
    }
}

@MainActor
@Observable
final class ProjectStore {
    private static let defaultUpdateBadgeRefreshInterval = Duration.seconds(60)
    private static let maximumUpdateBadgeRefreshInterval = Duration.seconds(15 * 60)

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
    var isShowingTemporaryFileCleanup = false {
        didSet {
            if !isShowingTemporaryFileCleanup, isCleaningSelectedProjectTemporaryFiles {
                isShowingTemporaryFileCleanup = true
            }
        }
    }
    var isShowingFileHistory = false
    var isShowingPathRecovery = false {
        didSet {
            if !isShowingPathRecovery, isPathRecoveryRunning {
                isShowingPathRecovery = true
            }
        }
    }
    var pathRecoveryPreview: SVNRecoveryPreview?
    var isShowingRepositoryPathNormalization = false
    var isConfirmingRepositoryPathNormalization = false
    var repositoryPathNormalizationTargets: [SVNRepositoryPathNormalizationTarget] = []
    var selectedRepositoryPathNormalizationTargets: Set<SVNRepositoryPathNormalizationTarget> = []
    var canBatchNormalizeRepositoryPaths = false
    var repositoryPathNormalizationCommitMessage = ""
    var repositoryPathNormalizationResult: SVNRepositoryPathNormalizationResult?
    var repositoryPathNormalizationIssue: RepositoryPathNormalizationIssue?
    var documentOpenRequest: DocumentOpenRequest?
    var activeConflictSession: ConflictResolutionSession?
    var activeTreeConflictSession: TreeConflictSession?
    var recoveryState = ProjectRecoveryState()
    var workingCopyCleanupRequest: WorkingCopyCleanupRequest?
    var canceledCheckoutRecoveryRequest: CanceledCheckoutRecoveryRequest?
    var forceUnlockRequest: ForceUnlockRequest?
    var resolvingConflictSessionID: ConflictResolutionSession.ID?
    var resolvingConflictProjectID: SVNProject.ID?
    var revertRequest: RevertRequest?
    var deletionRequest: DeletionRequest?
    var authenticationRequest: SVNAuthenticationRequest?
    var lastCompletedCommitMessage: String?
    var notice: String?
    var errorMessage: String?
    private(set) var checkoutLog = ""
    private(set) var commitLog = ""
    private(set) var hasFailedCommitLog = false
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
    var manualIgnorePattern: String {
        get { changesState.manualIgnorePattern }
        set { changesState.manualIgnorePattern = newValue }
    }
    var manualIgnoreDirectory: String {
        get { changesState.manualIgnoreDirectory }
        set { changesState.manualIgnoreDirectory = newValue }
    }
    var manualIgnorePropertyKind: SVNIgnorePropertyKind {
        get { changesState.manualIgnorePropertyKind }
        set { changesState.manualIgnorePropertyKind = newValue }
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
        set {
            changesState.selectedPaths = newValue
            removeUntrackedChildSelectionsCovered(by: newValue)
        }
    }
    var expandedUntrackedDirectoryPaths: Set<String> {
        get { changesState.expandedUntrackedDirectoryPaths }
        set { changesState.expandedUntrackedDirectoryPaths = newValue }
    }
    var untrackedChildrenByDirectory: [String: [SVNUntrackedChild]] {
        get { changesState.untrackedChildrenByDirectory }
        set { changesState.untrackedChildrenByDirectory = newValue }
    }
    var loadingUntrackedDirectoryPaths: Set<String> {
        get { changesState.loadingUntrackedDirectoryPaths }
        set { changesState.loadingUntrackedDirectoryPaths = newValue }
    }
    var untrackedChildrenErrorsByDirectory: [String: String] {
        get { changesState.untrackedChildrenErrorsByDirectory }
        set { changesState.untrackedChildrenErrorsByDirectory = newValue }
    }
    var selectedUntrackedChildPaths: Set<String> {
        get { changesState.selectedUntrackedChildPaths }
        set { changesState.selectedUntrackedChildPaths = newValue }
    }
    var untrackedChildrenRefreshGeneration: Int {
        get { changesState.untrackedChildrenRefreshGeneration }
        set { changesState.untrackedChildrenRefreshGeneration = newValue }
    }
    var selectedStatusPath: String? {
        get { changesState.selectedStatusPath }
        set { changesState.selectedStatusPath = newValue }
    }
    var hideTemporaryFiles: Bool {
        didSet {
            selectedPaths.formIntersection(selectableStatusPaths)
            if let selectedProjectID {
                updateLocalSummary(for: selectedProjectID, statuses: statuses)
            }
        }
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
        get { browserState.treeState.materializedTree }
        set { browserState.treeState = WorkingCopyBrowserTreeState(recursiveTree: newValue) }
    }
    var workingCopyBrowserTreeState: WorkingCopyBrowserTreeState {
        get { browserState.treeState }
        set { browserState.treeState = newValue }
    }
    var workingCopyBrowserSVNEntries: [SVNWorkingCopyEntry] {
        get { browserState.svnEntries }
        set { browserState.svnEntries = newValue }
    }
    var workingCopyBrowserRefreshGeneration: Int {
        get { browserState.refreshGeneration }
        set { browserState.refreshGeneration = newValue }
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
    var fileHistoryRequest: FileHistoryRequest? {
        get {
            if let request = recoveryState.commitHistoryRevisionOperationRequest {
                return request
            }
            if let restoreRequest = recoveryState.historyRevisionRestoreRequest,
               let context = recoveryState.historyRevisionActionContext,
               restoreRequest.fileHistoryRequestID == context.fileHistoryRequest.id {
                return context.fileHistoryRequest
            }
            return recoveryState.fileHistoryRequest
        }
        set {
            if recoveryState.routesNextFileHistoryRequestToCommitHistory {
                recoveryState.routesNextFileHistoryRequestToCommitHistory = false
            } else {
                recoveryState.fileHistoryRequest = newValue
            }
        }
    }

    func routeNextFileHistoryRequestToCommitHistory() {
        recoveryState.routesNextFileHistoryRequestToCommitHistory = true
    }

    func requestCommitHistoryRevisionRestore(
        fileHistoryRequest: FileHistoryRequest,
        revision: String
    ) {
        guard recoveryState.historyRevisionActionContext?.fileHistoryRequest == fileHistoryRequest
        else { return }
        recoveryState.commitHistoryRevisionOperationRequest = fileHistoryRequest
        defer { recoveryState.commitHistoryRevisionOperationRequest = nil }
        requestHistoryRevisionRestore(revision: revision)
    }

    func saveCommitHistoryRevision(
        _ request: HistoryRevisionSaveRequest,
        fileHistoryRequest: FileHistoryRequest
    ) async -> Bool {
        guard recoveryState.historyRevisionActionContext?.fileHistoryRequest == fileHistoryRequest
        else { return false }
        recoveryState.commitHistoryRevisionOperationRequest = fileHistoryRequest
        defer {
            if recoveryState.commitHistoryRevisionOperationRequest?.id == fileHistoryRequest.id {
                recoveryState.commitHistoryRevisionOperationRequest = nil
            }
        }
        return await saveHistoryRevision(request)
    }
    var remoteChanges: [SVNStatusEntry] {
        get { updateState.remoteChanges }
        set { updateState.remoteChanges = newValue }
    }
    var cleansRepositoryTemporaryFilesAfterUpdate: Bool {
        get { updateState.cleansRepositoryTemporaryFilesAfterUpdate }
        set { updateState.cleansRepositoryTemporaryFilesAfterUpdate = newValue }
    }
    var temporaryFileCleanupAssessments: [TemporaryFileCleanupAssessment] {
        get { updateState.temporaryFileCleanupAssessments }
        set { updateState.temporaryFileCleanupAssessments = newValue }
    }
    var selectedTemporaryFileCleanupPaths: Set<String> {
        get { updateState.selectedTemporaryFileCleanupPaths }
        set { updateState.selectedTemporaryFileCleanupPaths = newValue }
    }
    var temporaryFileCleanupFailures: [TemporaryFileCleanupFailure] {
        get { updateState.temporaryFileCleanupFailures }
        set { updateState.temporaryFileCleanupFailures = newValue }
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
    let workingCopyRecoveryFileManager: any WorkingCopyRecoveryFileManaging
    private let workspaceOpener: any WorkspaceOpening
    private let projectPathChecker: any ProjectPathChecking
    private let volumeNormalizationProbe: any VolumeNormalizationProbing
    let settingsDefaults: UserDefaults
    var sessionPasswords: [SVNProject.ID: String] = [:]
    var pathRecoverySourceProjectID: SVNProject.ID?
    var repositoryPathNormalizationSourceProjectID: SVNProject.ID?
    private var unavailableProjectID: SVNProject.ID?
    /// 요청 종류별 최신 토큰만 보존해 늦게 끝난 비동기 결과를 공통 규칙으로 폐기합니다.
    private var latestRequestIDs: [ProjectRequestKind: UUID] = [:]
    private var failedRefreshCycleIDs: Set<UUID> = []
    private var automaticRefreshBlockedProjectID: SVNProject.ID?
    private var filenameNormalizationProbeTasks: [SVNProject.ID: Task<Void, Never>] = [:]
    private let updateBadgePoller = UpdateBadgePoller()
    private var checkoutLogSessionID = UUID()
    private var commitLogSessionID = UUID()
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

    var isCommitInteractionLocked: Bool {
        isSelectedProjectActionBlocked || isCommittingSelectedProject
    }

    var showsCommitProgressLog: Bool {
        isCommittingSelectedProject || hasFailedCommitLog
    }

    var isLoadingSelectedProjectLocks: Bool {
        operationIsActive { .lock($0) }
    }

    var isCheckingOut: Bool {
        activeOperations.contains { $0.kind == .checkout }
    }

    var isCleaningSelectedWorkingCopy: Bool {
        guard let path = selectedProject?.path else { return false }
        return activeOperations.contains { $0.kind == .cleanupWorkingCopy(path) }
    }

    var isRecoveringCanceledCheckout: Bool {
        guard let path = canceledCheckoutRecoveryRequest?.destinationPath else { return false }
        return activeOperations.contains {
            $0.kind == .recoverCanceledCheckout(path) || $0.kind == .cleanupWorkingCopy(path)
        }
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
            switch operation.kind {
            case .relocate, .relocateRepository:
                true
            default:
                false
            }
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

    var isCleaningSelectedProjectTemporaryFiles: Bool {
        operationIsActive { .cleanupTemporaryFiles($0) }
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

    /// 변경 목록에 영향을 주는 새로고침만 봅니다. 커밋 기록 로딩은 변경 목록을 바꾸지 않으므로 제외합니다.
    var isRefreshingSelectedProjectChanges: Bool {
        guard let projectID = selectedProjectID else { return false }
        return activeOperations.contains { operation in
            switch operation.kind {
            case .refresh(let operationProjectID),
                 .refreshLocal(let operationProjectID):
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
            || isPreviewingSelectedProjectUpdate
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
            || isShowingTemporaryFileCleanup
            || isShowingLocks
            || authenticationRequest != nil
            || isShowingIgnoreRules
            || isShowingFileHistory
            || isShowingPathRecovery
            || isShowingRepositoryPathNormalization
            || activeConflictSession != nil
            || activeTreeConflictSession != nil
            || recoveryState.propertyConflictSession != nil
            || deletionRequest != nil
            || revertRequest != nil
            || documentOpenRequest != nil
    }

    var visibleStatuses: [SVNStatusEntry] {
        TemporaryFilePolicy.visibleEntries(statuses, hideTemporaryFiles: hideTemporaryFiles)
    }

    var visibleIgnoredStatuses: [SVNStatusEntry] {
        TemporaryFilePolicy.visibleEntries(ignoredStatuses, hideTemporaryFiles: hideTemporaryFiles)
    }

    var repositoryTemporaryFileCleanupCandidates: [SVNStatusEntry] {
        TemporaryFilePolicy.repositoryCleanupCandidates(in: remoteChanges)
    }

    var shouldOfferRepositoryTemporaryFileCleanup: Bool {
        !repositoryTemporaryFileCleanupCandidates.isEmpty
    }

    var selectableStatusPaths: Set<String> {
        Set(TemporaryFilePolicy.commitEligibleEntries(
            statuses,
            hideTemporaryFiles: hideTemporaryFiles
        ).map(\.path))
    }

    var selectAllStatusPaths: Set<String> {
        Set(TemporaryFilePolicy.automaticallySelectedEntries(statuses).map(\.path))
    }

    var canRepairCanonicalAliases: Bool {
        !pathCollisions.isEmpty && pathCollisions.allSatisfy { $0.repairableRawPath != nil }
    }

    var hasUnrepairablePathCollisions: Bool {
        pathCollisions.contains { $0.repairableRawPath == nil }
    }

    var shouldOfferNewWorkingFolderRecovery: Bool {
        hasUnrepairablePathCollisions
    }

    var canCommitSelectedPaths: Bool {
        let commitPaths = selectedCommitPaths()
        let knownChildPaths = Set(untrackedChildrenByDirectory.values.joined().map(\.path))
        return !hasUnrepairablePathCollisions
            && !commitPaths.isEmpty
            && selectedPaths.isSubset(of: selectableStatusPaths)
            && selectedUntrackedChildPaths.isSubset(of: knownChildPaths)
    }

    init(
        client: any SVNClientServing = SVNClient(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        persistence: any ProjectPersisting = UserDefaultsProjectPersistence(),
        projectAccessManager: any ProjectAccessManaging = SecurityScopedProjectAccessManager(),
        conflictFileService: ConflictFileService = ConflictFileService(),
        workingCopyFileService: any WorkingCopyFileListing = WorkingCopyFileService(),
        workingCopyRecoveryFileManager: any WorkingCopyRecoveryFileManaging = FileManagerWorkingCopyRecoveryFileManager(),
        workspaceOpener: any WorkspaceOpening = AppWorkspaceOpener(),
        projectPathChecker: any ProjectPathChecking = FileManagerProjectPathChecker(),
        volumeNormalizationProbe: any VolumeNormalizationProbing = CoreVolumeNormalizationProbe(),
        settingsDefaults: UserDefaults = .standard,
        hideTemporaryFiles: Bool = AppSettings.hideTemporaryFiles(),
        isDemoMode: Bool = false,
        updateBadgeRefreshInterval: Duration? = ProjectStore.defaultUpdateBadgeRefreshInterval,
        updateBadgeMaximumRefreshInterval: Duration = ProjectStore.maximumUpdateBadgeRefreshInterval,
        updateBadgeSleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.isDemoMode = isDemoMode
        self.hideTemporaryFiles = hideTemporaryFiles
        self.client = client
        self.credentialStore = credentialStore
        self.persistence = persistence
        self.projectAccessManager = projectAccessManager
        self.conflictFileService = conflictFileService
        self.workingCopyFileService = workingCopyFileService
        self.workingCopyRecoveryFileManager = workingCopyRecoveryFileManager
        self.workspaceOpener = workspaceOpener
        self.projectPathChecker = projectPathChecker
        self.volumeNormalizationProbe = volumeNormalizationProbe
        self.settingsDefaults = settingsDefaults

        var saved = persistence.loadProjects()
        projectAccessManager.restoreAccess(for: &saved)
        projects = saved
        selectedProjectID = saved.first?.id
        for project in saved { probeFilenameNormalization(for: project) }
        if !isDemoMode, let updateBadgeRefreshInterval {
            updateBadgePoller.start(
                interval: updateBadgeRefreshInterval,
                maximumInterval: updateBadgeMaximumRefreshInterval,
                sleep: updateBadgeSleep
            ) { [weak self] in
                await self?.refreshUpdateBadges() ?? true
            }
        }
    }

    // MARK: - 프로젝트 등록과 삭제

    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.current.localized(.ui.repository.chooseSvnLocalWorkingFolders)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        Task { await registerProjects(panel.urls) }
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
        recoveryState.canceledCheckoutRecoverySessionID = checkoutLogSessionID
        recoveryState.latestCanceledCheckoutRecoveryRequest = canceledCheckoutRecoveryRequest
        checkoutLog = ""
        let repositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryURL.isEmpty, let destinationURL else {
            errorMessage = AppLanguage.current.localized(.ui.checkout.localFolderRequiredError)
            return false
        }
        let destination = destinationURL.standardizedFileURL
        let destinationPath = destination.path
        let destinationWasEmpty = workingCopyRecoveryFileManager.isEmptyDirectory(at: destinationPath)
        guard !projects.contains(where: { $0.path == destinationPath }) else {
            errorMessage = AppLanguage.current.localized(.ui.recovery.localWorkingFolderAlreadyRegistered)
            return false
        }

        errorMessage = nil
        let operationID = beginOperation(.checkout)
        defer { endOperation(operationID) }

        // 체크아웃은 파일 시스템을 실제로 변경합니다. 체크아웃 성공 이후의
        // Keychain 저장 실패까지 전체 실패로 취급하면, 화면에는 실패라고 나오지만
        // 디스크에는 파일이 남는 모호한 상태가 됩니다. 그래서 경계를 둘로 나눕니다.
        let id = UUID()
        var bookmarkData: Data?
        let checkoutNotice: String
        let progressBuffer = CheckoutProgressBuffer()
        let checkoutCredentials = username.isEmpty
            ? nil
            : SVNCredentials(username: username, password: password.isEmpty ? nil : password)
        do {
            bookmarkData = try projectAccessManager.makeBookmark(for: destination)
            projectAccessManager.beginAccessing(destination, for: id)
            checkoutNotice = try await client.checkout(
                repositoryURL: repositoryURL,
                destinationPath: destinationPath,
                credentials: checkoutCredentials,
                allowUntrustedServerCertificate: allowsUntrustedServerCertificate,
                allowedServerCertificateFailures: allowsUntrustedServerCertificate
                    ? SVNProject.legacyAllowedServerCertificateFailures
                    : [],
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
            // 사용자가 직접 멈춘 작업은 실패가 아니므로 오류 대화상자를 띄우지 않습니다.
            if (error is CancellationError || Task.isCancelled), let bookmarkData {
                errorMessage = nil
                let preparedRecovery = await prepareCurrentCanceledCheckoutRecovery(
                    sessionID: checkoutLogSessionID,
                    id: id,
                    destination: destination,
                    username: username,
                    password: password,
                    bookmarkData: bookmarkData,
                    canEmptySafely: destinationWasEmpty,
                    allowsUntrustedServerCertificate: allowsUntrustedServerCertificate,
                    credentials: checkoutCredentials
                )
                guard let preparedRecovery else {
                    projectAccessManager.endAccessing(url: destination)
                    return false
                }
                if preparedRecovery {
                    notice = nil
                } else {
                    projectAccessManager.endAccessing(url: destination)
                    notice = AppLanguage.current.localized(
                        .ui.recovery.checkoutCanceledPartiallyDownloadedFilesMayRemain,
                        destinationPath
                    )
                }
                return false
            }
            if SVNClient.needsCleanup(error), let bookmarkData {
                let preparedRecovery = await prepareCurrentCanceledCheckoutRecovery(
                    sessionID: checkoutLogSessionID,
                    id: id,
                    destination: destination,
                    username: username,
                    password: password,
                    bookmarkData: bookmarkData,
                    canEmptySafely: destinationWasEmpty,
                    allowsUntrustedServerCertificate: allowsUntrustedServerCertificate,
                    credentials: checkoutCredentials
                )
                guard let preparedRecovery else {
                    projectAccessManager.endAccessing(url: destination)
                    return false
                }
                if preparedRecovery {
                    errorMessage = nil
                    return false
                }
            }
            projectAccessManager.endAccessing(url: destination)
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
                keychainWarning = AppLanguage.current.localized(.ui.authentication.checkoutCompletedButPasswordCouldNotSavedKeychain, localizedError(error))
            }
        }

        await refresh()
        // refresh의 완료 안내보다 자격 증명 보존 실패가 더 중요한 정보이므로
        // 마지막에 다시 적용해 사용자가 다음 실행에 대비할 수 있게 합니다.
        if let keychainWarning { notice = keychainWarning }
        return true
    }

    private func prepareCurrentCanceledCheckoutRecovery(
        sessionID: UUID,
        id: SVNProject.ID,
        destination: URL,
        username: String,
        password: String,
        bookmarkData: Data,
        canEmptySafely: Bool,
        allowsUntrustedServerCertificate: Bool,
        credentials: SVNCredentials?
    ) async -> Bool? {
        let prepared = await prepareCanceledCheckoutRecovery(
            id: id,
            destination: destination,
            username: username,
            password: password,
            bookmarkData: bookmarkData,
            canEmptySafely: canEmptySafely,
            allowsUntrustedServerCertificate: allowsUntrustedServerCertificate,
            credentials: credentials
        )
        guard recoveryState.canceledCheckoutRecoverySessionID == sessionID else {
            if canceledCheckoutRecoveryRequest?.id == id {
                canceledCheckoutRecoveryRequest = recoveryState.latestCanceledCheckoutRecoveryRequest
            }
            return nil
        }
        if prepared {
            recoveryState.latestCanceledCheckoutRecoveryRequest = canceledCheckoutRecoveryRequest
        }
        return prepared
    }

    func addProject(_ url: URL) {
        Task { await registerProjects([url]) }
    }

    func registerProjects(_ urls: [URL]) async {
        let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
            let standardizedURL = url.standardizedFileURL
            guard !result.contains(where: { $0.path == standardizedURL.path }) else { return }
            result.append(standardizedURL)
        }
        guard !uniqueURLs.isEmpty else { return }
        let sessionID = UUID()
        let selectedProjectIDAtStart = selectedProjectID
        recoveryState.projectRegistrationSessionID = sessionID
        let operationID = beginOperation(.registerProject)
        defer { endOperation(operationID) }

        var registeredProjects: [SVNProject] = []
        var lastFailureMessage: String?
        for url in uniqueURLs {
            let path = url.path
            guard !projects.contains(where: { $0.path == path }) else { continue }
            let projectID = UUID()
            do {
                let bookmarkData = try projectAccessManager.makeBookmark(for: url)
                projectAccessManager.beginAccessing(url, for: projectID)
                try await client.validateWorkingCopy(at: path, credentials: nil)
                guard !projects.contains(where: { $0.path == path }) else {
                    projectAccessManager.endAccessing(projectID: projectID)
                    continue
                }
                let project = SVNProject(id: projectID, name: url.lastPathComponent, path: path, bookmarkData: bookmarkData)
                projects.append(project)
                registeredProjects.append(project)
                probeFilenameNormalization(for: project)
            } catch {
                projectAccessManager.endAccessing(projectID: projectID)
                lastFailureMessage = localizedError(error)
            }
        }

        guard recoveryState.projectRegistrationSessionID == sessionID else { return }
        recoveryState.projectRegistrationSessionID = nil
        guard selectedProjectID == selectedProjectIDAtStart else { return }
        if let project = registeredProjects.first {
            selectedProjectID = project.id
            await refresh()
            guard selectedProjectID == project.id else { return }
        }
        if let lastFailureMessage { errorMessage = lastFailureMessage }
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
            errorMessage = AppLanguage.current.localized(.ui.recovery.localWorkingFolderAlreadyRegistered)
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
                .ui.repository.workingFolderChanged,
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
        guard !isDemoMode else { return }
        let project = selectedProject
        async let badgeRefresh = refreshUpdateBadges(excluding: project?.id)

        if let project {
            if manual {
                automaticRefreshBlockedProjectID = nil
                unavailableProjectID = nil
            }
            let canRefreshSelectedProject = manual || automaticRefreshCanRun(for: project)
            if canRefreshSelectedProject, ensureWorkingCopyDirectoryExists(for: project) {
                let cycleID = UUID()
                let errorPolicy = RefreshErrorPolicy.coordinated(cycleID)
                await refresh(errorPolicy: errorPolicy)
                finishRefreshCycle(cycleID)
            }
        }

        _ = await badgeRefresh
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
        let updateBadgeRequestID = beginRequest(.updateBadge(project.id))
        let operationID = beginOperation(.refresh(project.id))
        defer {
            finishRequest(updateBadgeRequestID, kind: .updateBadge(project.id))
            endOperation(operationID)
        }
        async let browserRefresh: Void = refreshWorkingCopyBrowser(errorPolicy: errorPolicy)

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
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            async let outOfDate = client.workingCopyIsOutOfDate(
                at: project.path,
                credentials: projectCredentials,
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            let (logs, isWorkingCopyOutOfDate) = try await (newLogs, outOfDate)
            guard canApplyRefresh(requestID, projectID: project.id) else { return }
            self.logs = logs
            self.hasMoreHistory = logs.count == 50
            if canApplyUpdateBadge(updateBadgeRequestID, project: project) {
                self.isWorkingCopyOutOfDate = isWorkingCopyOutOfDate
                updateRemoteSummary(for: project.id, needsUpdate: isWorkingCopyOutOfDate)
            }
            notice = AppLanguage.current.localized(.ui.common.refreshed, project.name)
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
        _ = await browserRefresh
    }

    private func prepareRefreshRequest() -> UUID {
        let requestID = registerRefreshRequest()
        isShowingPathRecovery = false
        pathRecoveryPreview = nil
        pathRecoverySourceProjectID = nil
        return requestID
    }

    private func registerRefreshRequest() -> UUID {
        hasFailedCommitLog = false
        discardUntrackedChildrenState()
        return beginRequest(.refresh)
    }

    @discardableResult
    func refreshUpdateBadges(excluding excludedProjectID: SVNProject.ID? = nil) async -> Bool {
        let projectsToRefresh = projects.filter { $0.id != excludedProjectID }
        var allRefreshesSucceeded = true
        for project in projectsToRefresh {
            guard !Task.isCancelled else { return false }
            if !(await refreshUpdateBadge(for: project)) {
                allRefreshesSucceeded = false
            }
        }
        return allRefreshesSucceeded
    }

    private func refreshUpdateBadge(for project: SVNProject) async -> Bool {
        guard projectPathChecker.directoryExists(at: project.path) else { return true }
        let requestKind = ProjectRequestKind.updateBadge(project.id)
        let requestID = beginRequest(requestKind)
        defer { finishRequest(requestID, kind: requestKind) }

        do {
            let projectCredentials = try credentials(for: project)
            let needsUpdate = try await client.workingCopyIsOutOfDate(
                at: project.path,
                credentials: projectCredentials,
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard canApplyUpdateBadge(requestID, project: project) else { return true }
            updateRemoteSummary(for: project.id, needsUpdate: needsUpdate)
            if selectedProjectID == project.id {
                isWorkingCopyOutOfDate = needsUpdate
            }
            return true
        } catch {
            return false
        }
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
            if let recovery = recoveryState.outOfDateCommitRecoveryRequest,
               recovery.projectID == project.id {
                selectedPaths.formUnion(recovery.paths)
            }
            selectedPaths.formIntersection(selectableStatusPaths)
            updateLocalSummary(for: project.id, statuses: snapshot.statuses)
            notice = AppLanguage.current.localized(.ui.changes.localChangesRefreshed, project.name)
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
        let isUntrackedChild = untrackedChildrenByDirectory.values.joined().contains {
            $0.path == path
        }
        if statuses.first(where: { $0.path == path })?.item == .unversioned || isUntrackedChild {
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
                if !offerWorkingCopyCleanup(for: error, projectID: project.id) {
                    errorMessage = localizedError(error)
                }
            }
        }
    }

    func commit(message: String) async -> Bool {
        guard let project = selectedProject, canCommitSelectedPaths else { return false }
        let selectedCommitPaths = selectedCommitPaths()
        let paths = selectedCommitPaths.sorted()
        let directoryRevisionUpdatePaths = Self.postCommitDirectoryRevisionUpdatePaths(
            committedPaths: paths,
            statuses: statuses,
            untrackedChildren: Array(untrackedChildrenByDirectory.values.joined())
        )
        let missingPaths = statuses.lazy
            .filter { $0.item == .missing && selectedCommitPaths.contains($0.path) }
            .map(\.path)
        guard missingPaths.isEmpty else {
            errorMessage = AppLanguage.current.localized(
                .error.deletion.chooseMissingItems,
                missingPaths.joined(separator: ", ")
            )
            return false
        }
        guard !Self.containsSelectedConflict(selectedPaths: selectedCommitPaths, statuses: statuses) else {
            errorMessage = AppLanguage.current.localized(.ui.conflict.resolveConflictedFilesBeforeCommitting)
            return false
        }
        let commitLogSessionID = UUID()
        self.commitLogSessionID = commitLogSessionID
        commitLog = ""
        hasFailedCommitLog = false
        let progressBuffer = CheckoutProgressBuffer()
        let operationID = beginOperation(.commit(project.id))
        var projectCredentials: SVNCredentials?
        defer {
            publishCommitLog(
                progressBuffer.output,
                sessionID: commitLogSessionID,
                projectID: project.id
            )
            endOperation(operationID)
        }
        do {
            projectCredentials = try credentials(for: project)
            _ = await directoryRevisionUpdateFailure(
                project: project,
                paths: directoryRevisionUpdatePaths,
                credentials: projectCredentials
            )
            guard selectedProjectID == project.id else { return false }
            let result = try await client.commit(
                at: project.path,
                paths: paths,
                message: message,
                credentials: projectCredentials,
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project),
                progress: { [weak self] output in
                    let accumulatedOutput = progressBuffer.append(output)
                    Task { @MainActor [weak self] in
                        self?.publishCommitLog(
                            accumulatedOutput,
                            sessionID: commitLogSessionID,
                            projectID: project.id
                        )
                    }
                }
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedProjectID == project.id { notice = result }
            let directoryRevisionUpdateFailure = await directoryRevisionUpdateFailure(
                project: project,
                paths: directoryRevisionUpdatePaths,
                credentials: projectCredentials
            )
            guard selectedProjectID == project.id else { return true }
            selectedPaths.subtract(paths)
            selectedUntrackedChildPaths.subtract(paths)
            lastCompletedCommitMessage = message
            recoveryState.outOfDateCommitRecoveryRequest = nil
            await refresh()
            guard selectedProjectID == project.id else { return true }
            if let directoryRevisionUpdateFailure {
                notice = [result, directoryRevisionUpdateFailure]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
            return true
        } catch let SVNError.commitSucceededWithValidationWarning(output, details) {
            let commitResult = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let validationWarning = localizedError(SVNError.commitSucceededWithValidationWarning(
                output: "",
                details: details
            ))
            if selectedProjectID == project.id {
                notice = [commitResult, validationWarning]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
            let directoryRevisionUpdateFailure = await directoryRevisionUpdateFailure(
                project: project,
                paths: directoryRevisionUpdatePaths,
                credentials: projectCredentials
            )
            guard selectedProjectID == project.id else { return true }
            selectedPaths.subtract(paths)
            selectedUntrackedChildPaths.subtract(paths)
            lastCompletedCommitMessage = message
            recoveryState.outOfDateCommitRecoveryRequest = nil
            await refresh()
            guard selectedProjectID == project.id else { return true }
            notice = [commitResult, validationWarning, directoryRevisionUpdateFailure]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return true
        } catch let error as SVNError {
            if selectedProjectID == project.id {
                hasFailedCommitLog = true
                if case let .workingCopyOutOfDate(details) = error {
                    isWorkingCopyOutOfDate = true
                    await prepareOutOfDateCommitRecovery(
                        project: project,
                        message: message,
                        paths: paths,
                        details: details
                    )
                } else {
                    handleRemoteError(error, project: project, action: .commit(message: message))
                }
            }
            return false
        } catch {
            if selectedProjectID == project.id {
                hasFailedCommitLog = true
                handleRemoteError(error, project: project, action: .commit(message: message))
            }
            return false
        }
    }

    nonisolated static func postCommitDirectoryRevisionUpdatePaths(
        committedPaths: [String],
        statuses: [SVNStatusEntry],
        untrackedChildren: [SVNUntrackedChild]
    ) -> [String] {
        let statusesByPath = Dictionary(
            statuses.map { (SVNPathIdentity(rawPath: $0.path), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let untrackedChildrenByPath = Dictionary(
            untrackedChildren.map { (SVNPathIdentity(rawPath: $0.path), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pathsByIdentity = [SVNPathIdentity(rawPath: "."): "."]

        for committedPath in committedPaths {
            let identity = SVNPathIdentity(rawPath: committedPath)
            let status = statusesByPath[identity]
            let isDeleted = status?.item == .deleted
            let isDirectory = status?.nodeKind == .directory
                || untrackedChildrenByPath[identity]?.isDirectory == true
            let directoryPath = isDeleted || !isDirectory
                ? Self.parentDirectory(of: committedPath)
                : committedPath
            pathsByIdentity[SVNPathIdentity(rawPath: directoryPath)] = directoryPath
        }

        return pathsByIdentity.values.sorted()
    }

    private nonisolated static func parentDirectory(of relativePath: String) -> String {
        guard relativePath != ".", let separator = relativePath.lastIndex(of: "/") else {
            return "."
        }
        let parent = relativePath[..<separator]
        return parent.isEmpty ? "." : String(parent)
    }

    private func directoryRevisionUpdateFailure(
        project: SVNProject,
        paths: [String],
        credentials: SVNCredentials?
    ) async -> String? {
        do {
            _ = try await client.updateDirectoryRevisions(
                at: project.path,
                relativePaths: paths,
                credentials: credentials,
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            return nil
        } catch {
            let details = if let svnError = error as? SVNError {
                SVNErrorLocalization.message(for: svnError, language: .current)
            } else {
                error.localizedDescription
            }
            return AppLanguage.current.localized(
                .ui.error.failed,
                "svn update --depth empty",
                details
            )
        }
    }

    private func publishCommitLog(
        _ output: String,
        sessionID: UUID,
        projectID: SVNProject.ID
    ) {
        guard commitLogSessionID == sessionID,
              selectedProjectID == projectID,
              output.utf8.count >= commitLog.utf8.count else { return }
        commitLog = output
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
    func saveFolderSettings(
        for projectID: SVNProject.ID,
        destinationURL: URL,
        username: String,
        newPassword: String,
        allowsUntrustedServerCertificate: Bool
    ) async -> FolderSettingsSaveResult {
        guard let originalProject = projects.first(where: { $0.id == projectID }) else {
            return .failed
        }
        let destination = destinationURL.standardizedFileURL
        let destinationPath = destination.path
        guard !projects.contains(where: { $0.id != projectID && $0.path == destinationPath }) else {
            errorMessage = AppLanguage.current.localized(.ui.recovery.localWorkingFolderAlreadyRegistered)
            return .failed
        }

        let operationID = beginOperation(.verifyCredentials(projectID))
        defer { endOperation(operationID) }
        do {
            let bookmarkData = destinationPath == originalProject.path
                ? originalProject.bookmarkData
                : try projectAccessManager.makeBookmark(for: destination)
            if destinationPath != originalProject.path {
                try await client.validateWorkingCopy(at: destinationPath, credentials: nil)
            }

            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectivePassword: String?
            if newPassword.isEmpty {
                if let sessionPassword = sessionPasswords[projectID] {
                    effectivePassword = sessionPassword
                } else {
                    effectivePassword = try credentialStore.password(for: projectID)
                }
            } else {
                effectivePassword = newPassword
            }
            let credentials = trimmedUsername.isEmpty
                ? nil
                : SVNCredentials(username: trimmedUsername, password: effectivePassword)
            var allowedFailures = originalProject.allowedServerCertificateFailures
            if allowsUntrustedServerCertificate {
                allowedFailures.formUnion(SVNProject.legacyAllowedServerCertificateFailures)
            } else {
                allowedFailures.subtract(SVNProject.legacyAllowedServerCertificateFailures)
            }
            do {
                try await client.verifyCredentials(
                    at: destinationPath,
                    credentials: credentials,
                    allowUntrustedServerCertificate: allowsUntrustedServerCertificate,
                    allowedServerCertificateFailures: allowedFailures
                )
            } catch {
                return .credentialFailure(localizedError(error))
            }

            guard let index = projects.firstIndex(where: {
                $0.id == projectID && $0.path == originalProject.path
            }), !projects.contains(where: {
                $0.id != projectID && $0.path == destinationPath
            }) else { return .failed }

            if !newPassword.isEmpty {
                try credentialStore.setPassword(newPassword, for: projectID)
            }
            var updatedProject = originalProject
            updatedProject.name = destination.lastPathComponent
            updatedProject.path = destinationPath
            updatedProject.username = trimmedUsername.isEmpty ? nil : trimmedUsername
            updatedProject.bookmarkData = bookmarkData
            updatedProject.allowsUntrustedServerCertificate = allowsUntrustedServerCertificate
            updatedProject.allowedServerCertificateFailures = allowedFailures

            if destinationPath != originalProject.path {
                projectAccessManager.endAccessing(projectID: projectID)
                projectAccessManager.beginAccessing(destination, for: projectID)
            }
            projects[index] = updatedProject
            if !newPassword.isEmpty { sessionPasswords[projectID] = newPassword }
            probeFilenameNormalization(for: updatedProject)
            notice = AppLanguage.current.localized(
                .ui.authentication.credentialsSaved,
                updatedProject.name
            )
            return .saved
        } catch {
            errorMessage = localizedError(error)
            return .failed
        }
    }

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
        var allowedServerCertificateFailures = project.allowedServerCertificateFailures
        if allowsUntrustedServerCertificate {
            allowedServerCertificateFailures.formUnion(SVNProject.legacyAllowedServerCertificateFailures)
        } else {
            allowedServerCertificateFailures.subtract(SVNProject.legacyAllowedServerCertificateFailures)
        }

        let operationID = beginOperation(.verifyCredentials(projectID))
        defer { endOperation(operationID) }
        do {
            try await client.verifyCredentials(
                at: project.path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowsUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
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
            var updatedProject = projects[index]
            updatedProject.username = username.isEmpty ? nil : username
            updatedProject.allowsUntrustedServerCertificate = allowsUntrustedServerCertificate
            if allowsUntrustedServerCertificate {
                updatedProject.allowedServerCertificateFailures.formUnion(
                    SVNProject.legacyAllowedServerCertificateFailures
                )
            } else {
                updatedProject.allowedServerCertificateFailures.subtract(
                    SVNProject.legacyAllowedServerCertificateFailures
                )
            }
            if !newPassword.isEmpty {
                try credentialStore.setPassword(newPassword, for: projectID)
                sessionPasswords[projectID] = newPassword
            }
            projects[index] = updatedProject
            notice = AppLanguage.current.localized(.ui.authentication.credentialsSaved, updatedProject.name)
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
            notice = AppLanguage.current.localized(.ui.authentication.savedPasswordDeleted)
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
            if saveInKeychain {
                try credentialStore.setPassword(password, for: request.projectID)
            }
            projects[index].username = username
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
        if request.serverCertificateTrust == nil {
            notice = AppLanguage.current.localized(.ui.authentication.canceledLocalChangesRemainAvailable)
        } else {
            notice = AppLanguage.current.localized(.ui.certificate.exceptionNotAllowedNoProjectSettingChanged)
        }
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

    func allowedServerCertificateFailures(
        for project: SVNProject
    ) -> Set<SVNServerCertificateFailure> {
        var failures = project.allowedServerCertificateFailures
        if project.allowsUntrustedServerCertificate == true {
            failures.formUnion(SVNProject.legacyAllowedServerCertificateFailures)
        }
        return failures
    }

    func allowServerCertificateFailure(for request: SVNAuthenticationRequest) async {
        guard authenticationRequest?.id == request.id,
              let trust = request.serverCertificateTrust,
              trust.canAllow,
              let index = projects.firstIndex(where: { $0.id == request.projectID }) else { return }
        projects[index].allowedServerCertificateFailures.formUnion(trust.failures)
        authenticationRequest = nil
        automaticRefreshBlockedProjectID = nil
        notice = AppLanguage.current.localized(
            .ui.certificate.savedCertificateExceptionRetrySvnOperation,
            projects[index].name
        )
        await resume(request)
    }

    func handleRemoteError(
        _ error: Error,
        project: SVNProject,
        action: SVNAuthenticationAction,
        refreshErrorPolicy: RefreshErrorPolicy = .standalone
    ) {
        if presentServerCertificateTrustRequest(
            for: error,
            project: project,
            action: action
        ) {
            return
        }
        if isKeychainAccessDenied(error) {
            isShowingUpdatePreview = false
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
            if !offerWorkingCopyCleanup(for: error, projectID: projectID) {
                errorMessage = localizedError(error)
            }
        case let .coordinated(cycleID):
            guard failedRefreshCycleIDs.insert(cycleID).inserted else { return }
            automaticRefreshBlockedProjectID = projectID
            if !offerWorkingCopyCleanup(for: error, projectID: projectID) {
                errorMessage = localizedError(error)
            }
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
        AppLanguage.current.localized(.ui.authentication.keychainAccessDeniedChooseHowAuthenticate)
    }

    private func resume(_ request: SVNAuthenticationRequest) async {
        guard selectedProjectID == request.projectID else { return }
        switch request.action {
        case .refreshHistory:
            await refreshRemoteHistory(for: request.projectID)
        case .update:
            if recoveryState.outOfDateCommitRecoveryRequest?.projectID == request.projectID {
                await previewUpdate(mode: .outOfDateCommitRecovery)
            } else {
                await update()
            }
        case let .commit(message):
            if let recovery = recoveryState.outOfDateCommitRecoveryRequest,
               recovery.projectID == request.projectID,
               !recovery.hasCompletedUpdate {
                await update()
            } else {
                // 삭제(missing) 항목을 포함한 선택도 재시도할 수 있어야 합니다.
                _ = await commitSelectedChanges(message: message)
            }
        case .retryManually:
            break
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
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id else { return }
            logs = newLogs
            hasMoreHistory = newLogs.count == 50
            notice = AppLanguage.current.localized(.ui.history.refreshed, project.name)
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .refreshHistory)
            }
        }
    }

    func localizedError(_ error: Error, language: AppLanguage = .current) -> String {
        if let project = selectedProject,
           presentServerCertificateTrustRequest(
               for: error,
               project: project,
               action: .retryManually
           ),
           let trust = authenticationRequest?.serverCertificateTrust {
            return trust.failures
                .map { SVNErrorLocalization.serverCertificateGuidance(for: $0, language: language) }
                .joined(separator: "\n\n")
        }
        if let conflictError = error as? ConflictFileError {
            return SVNErrorLocalization.message(for: conflictError, language: language)
        }
        if let svnError = error as? SVNError {
            return SVNErrorLocalization.message(for: svnError, language: language)
        }
        return error.localizedDescription
    }

    private func presentServerCertificateTrustRequest(
        for error: Error,
        project: SVNProject,
        action: SVNAuthenticationAction
    ) -> Bool {
        guard let detectedFailures = SVNErrorLocalization.serverCertificateFailures(for: error)
        else { return false }
        let failuresNeedingConsent = detectedFailures.subtracting(
            allowedServerCertificateFailures(for: project)
        )
        guard !failuresNeedingConsent.isEmpty else { return false }
        isShowingUpdatePreview = false
        authenticationRequest = SVNAuthenticationRequest(
            projectID: project.id,
            action: action,
            serverCertificateTrust: ServerCertificateTrust(
                failures: failuresNeedingConsent,
                diagnosticDetails: SVNErrorLocalization.diagnosticDetails(for: error)
            )
        )
        errorMessage = nil
        return true
    }

    func openFile(_ relativePath: String, in project: SVNProject) {
        let url = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath)
        guard workspaceOpener.open(url) else {
            errorMessage = AppLanguage.current.localized(.ui.error.unableOpenFile, relativePath)
            return
        }
    }

    func openWorkspaceURL(_ url: URL) {
        guard workspaceOpener.open(url) else {
            errorMessage = AppLanguage.current.localized(.ui.common.couldNotOpenFile)
            return
        }
    }

    private func save() {
        // 프로젝트 목록 변경마다 즉시 저장해 앱이 비정상 종료되어도 최근 등록 및
        // 삭제 상태를 최대한 보존합니다. 인코딩 실패 시 기존 저장값은 유지합니다.
        persistence.saveProjects(projects)
    }

    func registerRecoveredCheckout(_ project: SVNProject) {
        projects.append(project)
        selectedProjectID = project.id
        probeFilenameNormalization(for: project)
    }

    func clearAutomaticRefreshBlock(for projectID: SVNProject.ID) {
        if automaticRefreshBlockedProjectID == projectID {
            automaticRefreshBlockedProjectID = nil
        }
    }

    func updateLocalSummary(for projectID: SVNProject.ID, statuses: [SVNStatusEntry]) {
        let visibleStatuses = TemporaryFilePolicy.visibleEntries(
            statuses,
            hideTemporaryFiles: hideTemporaryFiles
        )
        var summary = projectSummaries[projectID] ?? ProjectStatusSummary()
        summary.localChangeCount = visibleStatuses.count
        summary.conflictCount = visibleStatuses.filter {
            $0.item == .conflicted || $0.propertyState == .conflicted
        }.count
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
        commitLogSessionID = UUID()
        commitLog = ""
        hasFailedCommitLog = false
        failedRefreshCycleIDs = []
        automaticRefreshBlockedProjectID = nil
        changesState = ProjectChangesStore()
        browserState = ProjectBrowserStore()
        historyState = ProjectHistoryStore()
        updateState = ProjectUpdateStore()
        pathRecoveryPreview = nil
        pathRecoverySourceProjectID = nil
        isShowingPathRecovery = false
        isShowingUpdatePreview = false
        isShowingTemporaryFileCleanup = false
        isShowingFileHistory = false
        isShowingLocks = false
        isShowingIgnoreRules = false
        isShowingCredentials = false
        requiresGlobalIgnoreImportConfirmation = false
        selectedBrowserPath = nil
        documentOpenRequest = nil
        activeConflictSession = nil
        activeTreeConflictSession = nil
        recoveryState = ProjectRecoveryState()
        workingCopyCleanupRequest = nil
        forceUnlockRequest = nil
        resolvingConflictSessionID = nil
        resolvingConflictProjectID = nil
        revertRequest = nil
        deletionRequest = nil
        isShowingRepositoryPathNormalization = false
        isConfirmingRepositoryPathNormalization = false
        repositoryPathNormalizationTargets = []
        selectedRepositoryPathNormalizationTargets = []
        canBatchNormalizeRepositoryPaths = false
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
            errorMessage = AppLanguage.current.localized(.ui.repository.workingFolderNoLongerExistsRestoreFolderRemoveItList, project.name, project.path)
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

    private func canApplyUpdateBadge(_ requestID: UUID, project: SVNProject) -> Bool {
        latestRequestIDs[.updateBadge(project.id)] == requestID
            && projects.contains { $0.id == project.id && $0.path == project.path }
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
