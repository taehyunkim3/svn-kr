import AppKit
import Foundation
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
            language.text("변경 파일을 선택하면 diff가 표시됩니다.", "Select a changed file to view its diff.")
        case .unavailableForUnversioned:
            language.text(
                "아직 SVN에 추가되지 않은 파일은 diff를 표시할 수 없습니다. 커밋할 때 자동으로 추가됩니다.",
                "Diff is unavailable until this file is added to SVN. It will be added automatically when committed."
            )
        case .noTextDiff:
            language.text(
                "텍스트 diff가 없습니다. 새 파일 또는 바이너리 파일일 수 있습니다.",
                "No text diff is available. This may be a new or binary file."
            )
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

struct SVNAuthenticationRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let action: SVNAuthenticationAction
}

@MainActor
final class ProjectStore: ObservableObject {
    // MARK: - 화면에 공개하는 상태

    @Published var projects: [SVNProject] = [] { didSet { save() } }
    @Published var selectedProjectID: SVNProject.ID? {
        didSet {
            guard selectedProjectID != oldValue else { return }
            resetSelectedProjectState()
        }
    }
    @Published var statuses: [SVNStatusEntry] = []
    @Published var pathCollisions: [SVNPathCollision] = []
    @Published var ignoredStatuses: [SVNStatusEntry] = []
    @Published var ignoreRules: [SVNIgnoreRule] = []
    @Published var gitIgnoreImportItems: [IgnoreImportItem] = []
    @Published var selectedGitIgnoreImportIDs: Set<IgnoreImportItem.ID> = []
    @Published var hasComparedGitIgnore = false
    @Published var gitIgnoreFileExists = false
    @Published var gitIgnoreLastComparedAt: Date?
    @Published var requiresGlobalIgnoreImportConfirmation = false
    @Published var repositoryLocks: [SVNLockInfo] = []
    @Published var workingCopyFileTree: [WorkingCopyFileNode] = []
    @Published var selectedBrowserPath: String?
    @Published var remoteChanges: [SVNStatusEntry] = []
    @Published var projectSummaries: [SVNProject.ID: ProjectStatusSummary] = [:]
    @Published var fileHistory: [SVNLogEntry] = []
    @Published var fileHistoryPath: String?
    @Published var showsIgnoredFiles = false
    @Published var logs: [SVNLogEntry] = []
    @Published var selectedHistoryRevision: String?
    @Published var selectedHistoryPath: String?
    @Published var historyDiffContent: DiffContent = .placeholder
    @Published var hasMoreHistory = true
    @Published var workingCopyRevision: SVNWorkingCopyRevision?
    @Published var workingCopyRepositoryPath: String?
    @Published var isWorkingCopyOutOfDate: Bool?
    @Published var selectedPaths: Set<String> = []
    @Published var selectedStatusPath: String?
    @Published var diffContent: DiffContent = .placeholder
    @Published private(set) var activeOperations: [ProjectOperation] = []
    @Published var isShowingAddRepository = false
    @Published var isShowingCredentials = false
    @Published var isShowingIgnoreRules = false
    @Published var isShowingLocks = false
    @Published var isShowingUpdatePreview = false
    @Published var isShowingFileHistory = false
    @Published var isShowingPathRecovery = false
    @Published var pathRecoveryPreview: SVNRecoveryPreview?
    @Published var documentOpenRequest: DocumentOpenRequest?
    @Published var activeConflictSession: ConflictResolutionSession?
    @Published var resolvingConflictSessionID: ConflictResolutionSession.ID?
    @Published var resolvingConflictProjectID: SVNProject.ID?
    @Published var revertRequest: RevertRequest?
    @Published var deletionRequest: DeletionRequest?
    @Published var authenticationRequest: SVNAuthenticationRequest?
    @Published var lastCompletedCommitMessage: String?
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published private(set) var checkoutLog = ""

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
    var sessionPasswords: [SVNProject.ID: String] = [:]
    var pathRecoverySourceProjectID: SVNProject.ID?
    private var unavailableProjectID: SVNProject.ID?
    /// 새 refresh가 시작되거나 프로젝트가 바뀌면 이전 결과를 폐기하기 위한 토큰입니다.
    private var refreshRequestID: UUID?
    /// 빠르게 여러 파일을 선택했을 때 늦게 끝난 이전 diff가 덮어쓰지 않게 합니다.
    private var diffRequestID: UUID?
    var fileTreeRequestID: UUID?
    var repositoryLocksRequestID: UUID?
    var conflictPreparationRequestID: UUID?
    private var failedRefreshCycleIDs: Set<UUID> = []
    private var automaticRefreshBlockedProjectID: SVNProject.ID?
    private var checkoutLogSessionID = UUID()

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

    var isPathRecoveryRunning: Bool {
        guard let projectID = pathRecoverySourceProjectID else { return false }
        return activeOperations.contains { $0.kind == .recover(projectID) }
    }

    var showsGlobalProgress: Bool {
        isWorking && !isCommittingSelectedProject
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

        var saved = persistence.loadProjects()
        projectAccessManager.restoreAccess(for: &saved)
        projects = saved
        selectedProjectID = saved.first?.id
    }

    // MARK: - 프로젝트 등록과 삭제

    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.current.text("SVN 로컬 작업 폴더 선택", "Choose SVN Local Working Folders")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addProject(url) }
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
            errorMessage = AppLanguage.current.text(
                "체크아웃할 로컬 폴더를 선택해 주세요.",
                "Choose a local folder for the checkout."
            )
            return false
        }
        let destination = destinationURL.standardizedFileURL
        let destinationPath = destination.path
        guard !projects.contains(where: { $0.path == destinationPath }) else {
            errorMessage = AppLanguage.current.text("이미 등록된 로컬 작업 폴더입니다.", "This local working folder is already registered.")
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
        notice = checkoutNotice

        var keychainWarning: String?
        if !password.isEmpty {
            // Keychain 저장이 실패해도 이번 실행의 인증과 체크아웃 결과는 유지합니다.
            sessionPasswords[id] = password
            do {
                try credentialStore.setPassword(password, for: id)
            } catch {
                keychainWarning = AppLanguage.current.text(
                    "체크아웃은 완료했지만 비밀번호를 Keychain에 저장하지 못했습니다: \(localizedError(error))",
                    "Checkout completed, but the password could not be saved in Keychain: \(localizedError(error))"
                )
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
                await refresh()
            } catch {
                projectAccessManager.endAccessing(projectID: projectID)
                errorMessage = localizedError(error)
            }
        }
    }

    func removeSelectedProject() {
        if let selectedProjectID {
            sessionPasswords[selectedProjectID] = nil
            try? credentialStore.deletePassword(for: selectedProjectID)
            projectAccessManager.endAccessing(projectID: selectedProjectID)
            projectSummaries[selectedProjectID] = nil
        }
        projects.removeAll { $0.id == selectedProjectID }
        selectedProjectID = projects.first?.id
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
            notice = AppLanguage.current.text("\(project.name) 새로고침 완료", "\(project.name) refreshed")
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
        let requestID = UUID()
        refreshRequestID = requestID
        return requestID
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
            notice = AppLanguage.current.text(
                "\(project.name) 로컬 변경 사항 확인 완료",
                "\(project.name) local changes refreshed"
            )
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
        let requestID = UUID()
        diffRequestID = requestID
        selectedStatusPath = path
        if statuses.first(where: { $0.path == path })?.item == .unversioned {
            diffContent = .unavailableForUnversioned
            return
        }
        do {
            let value = try await client.diff(at: project.path, relativePath: path, credentials: nil)
            guard diffRequestID == requestID,
                  selectedProjectID == project.id,
                  selectedStatusPath == path else { return }
            diffContent = value.isEmpty ? .noTextDiff : .text(value)
        } catch {
            if diffRequestID == requestID, selectedProjectID == project.id {
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
            errorMessage = AppLanguage.current.text(
                "먼저 로컬 누락 항목의 처리 방법을 선택하세요: \(missingPaths.joined(separator: ", "))",
                "Choose how to handle locally missing items first: \(missingPaths.joined(separator: ", "))"
            )
            return false
        }
        guard !Self.containsSelectedConflict(selectedPaths: selectedPaths, statuses: statuses) else {
            errorMessage = AppLanguage.current.text("충돌 파일은 해결 완료 처리 후 커밋할 수 있습니다.", "Resolve conflicted files before committing.")
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
            notice = AppLanguage.current.text("\(projects[index].name) 인증 설정 저장 완료", "Credentials saved for \(projects[index].name)")
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
            notice = AppLanguage.current.text("저장된 비밀번호를 삭제했습니다.", "The saved password was deleted.")
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
        notice = AppLanguage.current.text(
            "인증을 취소했습니다. 로컬 변경 사항은 계속 확인할 수 있습니다.",
            "Authentication was canceled. Local changes remain available."
        )
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
        AppLanguage.current.text(
            "Keychain 접근이 거부되었습니다. 인증 방식을 다시 선택할 수 있습니다.",
            "Keychain access was denied. Choose how to authenticate."
        )
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
            notice = AppLanguage.current.text("\(project.name) 커밋 기록 확인 완료", "\(project.name) history refreshed")
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .refreshHistory)
            }
        }
    }

    func localizedError(_ error: Error, language: AppLanguage = .current) -> String {
        if let conflictError = error as? ConflictFileError {
            return localizedConflictFileError(conflictError, language: language)
        }
        guard language == .english, let svnError = error as? SVNError else {
            return error.localizedDescription
        }
        switch svnError {
        case let .commandFailed(command, message):
            return "\(command) failed: \(message)"
        case let .workingCopyOutOfDate(details):
            return "The commit is based on an older working-copy state. Run Update, resolve any conflicts, and then commit again.\n\n\(details)"
        case .invalidWorkingCopy:
            return "The selected folder is not an SVN local working folder."
        case .malformedResponse:
            return "The SVN response could not be read."
        case let .pathNormalizationCollision(paths):
            return "Korean path normalization conflicts must be recovered before continuing: \(paths.joined(separator: ", "))"
        case let .pathAliasRepairFailed(paths):
            return "Korean path alias repair could not be validated: \(paths.joined(separator: ", "))"
        case let .fileReplacementRecoveryFailed(paths, backupPaths):
            return "Replacement files could not be restored to their original paths: \(paths.joined(separator: ", ")). Backups: \(backupPaths.joined(separator: ", "))"
        case let .unsupportedTargetPath(paths):
            return "Paths containing line breaks cannot be passed safely to SVN: \(paths.joined(separator: ", "))"
        case let .unresolvedMissingPaths(paths):
            return "Choose how to handle locally missing items first: \(paths.joined(separator: ", "))"
        case let .deletionValidationFailed(paths):
            return "These items did not enter the pending-deletion state: \(paths.joined(separator: ", "))"
        case let .commitSucceededWithValidationWarning(_, details):
            return "The commit completed, but working-copy validation failed. Do not retry the commit; review the refreshed status: \(details)"
        case let .recoveryBlocked(paths):
            return "Some changes cannot be recovered automatically: \(paths.joined(separator: ", "))"
        case .recoveryDestinationNotEmpty:
            return "The recovery destination folder must be empty."
        case let .recoveryValidationFailed(paths):
            return "The recovered working copy did not pass validation: \(paths.joined(separator: ", "))"
        case .svnExecutableNotFound:
            return "The bundled SVN executable could not be found. Reinstall the app."
        }
    }

    private func localizedConflictFileError(
        _ error: ConflictFileError,
        language: AppLanguage
    ) -> String {
        switch error {
        case let .unsupportedType(type):
            return language.text("지원하지 않는 충돌 유형입니다: \(type)", "Unsupported conflict type: \(type)")
        case .missingMine:
            return language.text("내 파일 버전을 찾을 수 없습니다.", "Your file version could not be found.")
        case .missingServer:
            return language.text("서버 파일 버전을 찾을 수 없습니다.", "The server file version could not be found.")
        case .missingWorkingFile:
            return language.text("현재 작업 파일을 찾을 수 없습니다.", "The current working file could not be found.")
        case .sourceOutsideWorkingCopy:
            return language.text("충돌 파일 경로가 작업 사본 밖을 가리킵니다.", "A conflict file path points outside the working copy.")
        case .backupRootInsideWorkingCopy:
            return language.text("충돌 백업 위치는 작업 사본 밖에 있어야 합니다.", "Conflict backups must be stored outside the working copy.")
        case .unsafeMineSource:
            return language.text("내 파일 버전은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다.", "Your file version must be a regular file, not a symbolic link.")
        case .unsafeServerSource:
            return language.text("서버 파일 버전은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다.", "The server file version must be a regular file, not a symbolic link.")
        case .unsafeWorkingFile:
            return language.text("현재 작업 파일은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다.", "The current working file must be a regular file, not a symbolic link.")
        case .workingRecoveryVerificationFailed:
            return language.text("현재 작업 파일의 복구 백업을 검증하지 못했습니다.", "The recovery backup of the current working file could not be verified.")
        case .workingRestoreVerificationFailed:
            return language.text("선택한 내 파일 버전을 작업 파일에 복원하지 못했습니다.", "The selected version of your file could not be restored to the working file.")
        case .conflictResolutionVerificationFailed:
            return language.text(
                "SVN 명령 이후에도 충돌 상태가 남아 있습니다. 백업을 확인한 뒤 다시 시도하세요.",
                "The conflict remains after the SVN command. Review the backups and try again."
            )
        case let .cleanupFailed(message):
            return language.text("불완전한 충돌 백업 정리에 실패했습니다: \(message)", "Failed to remove an incomplete conflict backup: \(message)")
        }
    }

    func openFile(_ relativePath: String, in project: SVNProject) {
        let url = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath)
        guard workspaceOpener.open(url) else {
            errorMessage = AppLanguage.current.text("파일을 열 수 없습니다: \(relativePath)", "Unable to open file: \(relativePath)")
            return
        }
    }

    func openWorkspaceURL(_ url: URL) {
        guard workspaceOpener.open(url) else {
            errorMessage = AppLanguage.current.text("파일을 열 수 없습니다.", "Could not open the file.")
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
        refreshRequestID = nil
        diffRequestID = nil
        fileTreeRequestID = nil
        repositoryLocksRequestID = nil
        conflictPreparationRequestID = nil
        failedRefreshCycleIDs = []
        automaticRefreshBlockedProjectID = nil
        statuses = []
        pathCollisions = []
        ignoredStatuses = []
        ignoreRules = []
        gitIgnoreImportItems = []
        selectedGitIgnoreImportIDs = []
        hasComparedGitIgnore = false
        gitIgnoreFileExists = false
        gitIgnoreLastComparedAt = nil
        requiresGlobalIgnoreImportConfirmation = false
        repositoryLocks = []
        workingCopyFileTree = []
        selectedBrowserPath = nil
        remoteChanges = []
        fileHistory = []
        fileHistoryPath = nil
        showsIgnoredFiles = false
        documentOpenRequest = nil
        activeConflictSession = nil
        resolvingConflictSessionID = nil
        resolvingConflictProjectID = nil
        revertRequest = nil
        deletionRequest = nil
        logs = []
        selectedHistoryRevision = nil
        selectedHistoryPath = nil
        historyDiffContent = .placeholder
        hasMoreHistory = true
        workingCopyRevision = nil
        workingCopyRepositoryPath = nil
        isWorkingCopyOutOfDate = nil
        selectedPaths = []
        selectedStatusPath = nil
        diffContent = .placeholder
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
            errorMessage = AppLanguage.current.text(
                "'\(project.name)' 작업 폴더가 존재하지 않습니다.\n\(project.path)\n\n폴더를 복원하거나 왼쪽 아래 − 버튼으로 목록에서 제거하세요.",
                "The '\(project.name)' working folder no longer exists.\n\(project.path)\n\nRestore the folder or remove it from the list with the − button."
            )
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
        refreshRequestID == requestID && selectedProjectID == projectID
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
