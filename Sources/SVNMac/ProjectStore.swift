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
        }
    }
}

enum SVNAuthenticationAction: Equatable {
    case refreshHistory
    case update
    case commit(message: String)
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
    @Published var ignoredStatuses: [SVNStatusEntry] = []
    @Published var ignoreRules: [SVNIgnoreRule] = []
    @Published var repositoryLocks: [SVNLockInfo] = []
    @Published var remoteChanges: [SVNStatusEntry] = []
    @Published var projectSummaries: [SVNProject.ID: ProjectStatusSummary] = [:]
    @Published var fileHistory: [SVNLogEntry] = []
    @Published var fileHistoryPath: String?
    @Published var showsIgnoredFiles = false
    @Published var logs: [SVNLogEntry] = []
    @Published var selectedHistoryRevision: String?
    @Published var historyDiffContent: DiffContent = .placeholder
    @Published var hasMoreHistory = true
    @Published var workingCopyRevision: String?
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
    @Published var documentOpenRequest: DocumentOpenRequest?
    @Published var activeConflict: SVNConflictDetails?
    @Published var revertRequest: RevertRequest?
    @Published var authenticationRequest: SVNAuthenticationRequest?
    @Published var lastCompletedCommitMessage: String?
    @Published var notice: String?
    @Published var errorMessage: String?

    // MARK: - 외부 서비스와 비동기 작업 추적

    private let client: any SVNClientServing
    private let credentialStore: any CredentialStoring
    private let persistence: any ProjectPersisting
    private let projectAccessManager: any ProjectAccessManaging
    private let conflictFileService: ConflictFileService
    private var sessionPasswords: [SVNProject.ID: String] = [:]
    /// 새 refresh가 시작되거나 프로젝트가 바뀌면 이전 결과를 폐기하기 위한 토큰입니다.
    private var refreshRequestID: UUID?
    /// 빠르게 여러 파일을 선택했을 때 늦게 끝난 이전 diff가 덮어쓰지 않게 합니다.
    private var diffRequestID: UUID?

    var selectedProject: SVNProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var isWorking: Bool { !activeOperations.isEmpty }

    init(
        client: any SVNClientServing = SVNClient(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        persistence: any ProjectPersisting = UserDefaultsProjectPersistence(),
        projectAccessManager: any ProjectAccessManaging = SecurityScopedProjectAccessManager(),
        conflictFileService: ConflictFileService = ConflictFileService()
    ) {
        self.client = client
        self.credentialStore = credentialStore
        self.persistence = persistence
        self.projectAccessManager = projectAccessManager
        self.conflictFileService = conflictFileService

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
        do {
            bookmarkData = try projectAccessManager.makeBookmark(for: destination)
            projectAccessManager.beginAccessing(destination, for: id)
            let credentials = username.isEmpty ? nil : SVNCredentials(username: username, password: password.isEmpty ? nil : password)
            checkoutNotice = try await client.checkout(
                repositoryURL: repositoryURL,
                destinationPath: destinationPath,
                credentials: credentials,
                allowUntrustedServerCertificate: allowsUntrustedServerCertificate
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
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

    func refresh() async {
        guard let project = selectedProject else { return }
        let requestID = UUID()
        refreshRequestID = requestID
        let operationID = beginOperation(.refresh(project.id))
        defer { endOperation(operationID) }
        isWorkingCopyOutOfDate = nil
        do {
            async let newStatuses = client.status(at: project.path, credentials: nil)
            async let newWorkingCopyRevision = client.workingCopyRevision(at: project.path, credentials: nil)
            let (statuses, workingCopyRevision) = try await (newStatuses, newWorkingCopyRevision)
            guard canApplyRefresh(requestID, projectID: project.id) else { return }
            self.statuses = statuses
            self.workingCopyRevision = workingCopyRevision
            selectedPaths.formIntersection(Set(statuses.filter { $0.item != .conflicted }.map(\.path)))
            updateLocalSummary(for: project.id, statuses: statuses)
            notice = AppLanguage.current.text("\(project.name) 로컬 변경 사항 확인 완료", "\(project.name) local changes refreshed")
        } catch {
            if canApplyRefresh(requestID, projectID: project.id) {
                errorMessage = localizedError(error)
            }
            return
        }

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
                handleRemoteError(error, project: project, action: .refreshHistory)
            }
        }
    }

    func update() async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.update(project.id))
        defer { endOperation(operationID) }
        do {
            let result = try await client.update(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedProjectID == project.id else { return }
            notice = result
            isShowingUpdatePreview = false
            await refresh()
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .update)
            }
        }
    }

    func previewUpdate() async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.previewUpdate(project.id))
        defer { endOperation(operationID) }
        do {
            remoteChanges = try await client.remoteChanges(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            updateRemoteSummary(for: project.id, needsUpdate: !remoteChanges.isEmpty)
            isShowingUpdatePreview = true
        } catch {
            handleRemoteError(error, project: project, action: .update)
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

    func setShowsIgnoredFiles(_ showsIgnoredFiles: Bool) async {
        self.showsIgnoredFiles = showsIgnoredFiles
        guard showsIgnoredFiles, let project = selectedProject else {
            ignoredStatuses = []
            return
        }
        do {
            ignoredStatuses = try await client.ignoredStatus(at: project.path, credentials: nil)
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func loadIgnoreRules() async {
        guard let project = selectedProject else { return }
        do {
            ignoreRules = try await client.ignoreRules(at: project.path, credentials: nil)
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func ignore(path relativePath: String, byExtension: Bool) async {
        guard let project = selectedProject else { return }
        let path = relativePath as NSString
        let directory = path.deletingLastPathComponent.isEmpty ? "." : path.deletingLastPathComponent
        let pattern: String
        if byExtension, !path.pathExtension.isEmpty {
            pattern = "*.\(path.pathExtension)"
        } else {
            pattern = path.lastPathComponent
        }
        let operationID = beginOperation(.ignore(project.id))
        defer { endOperation(operationID) }
        do {
            try await client.addIgnoreRule(at: project.path, directory: directory, pattern: pattern, credentials: nil)
            notice = AppLanguage.current.text("무시 규칙 '\(pattern)'을 추가했습니다. 디렉터리 속성을 커밋하면 팀에 공유됩니다.", "Added ignore rule '\(pattern)'. Commit the directory property to share it with the team.")
            await refresh()
            await loadIgnoreRules()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func removeIgnoreRule(_ rule: SVNIgnoreRule) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.ignore(project.id))
        defer { endOperation(operationID) }
        do {
            try await client.removeIgnoreRule(at: project.path, directory: rule.directory, pattern: rule.pattern, credentials: nil)
            notice = AppLanguage.current.text("무시 규칙 '\(rule.pattern)'을 제거했습니다.", "Removed ignore rule '\(rule.pattern)'.")
            await refresh()
            await loadIgnoreRules()
            if showsIgnoredFiles { await setShowsIgnoredFiles(true) }
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func prepareToOpen(path relativePath: String) async {
        guard let project = selectedProject else { return }
        guard DocumentFilePolicy.recommendsLock(for: relativePath) else {
            openFile(relativePath, in: project)
            return
        }
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let existingLock = try await client.lockInfo(
                at: project.path,
                relativePath: relativePath,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            documentOpenRequest = DocumentOpenRequest(relativePath: relativePath, existingLock: existingLock)
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func lockAndOpen(_ request: DocumentOpenRequest) async {
        guard let project = selectedProject else { return }
        documentOpenRequest = nil
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let comment = AppLanguage.current.text("SVN Mac에서 문서 편집 중", "Editing document in SVN Mac")
            _ = try await client.lock(
                at: project.path,
                relativePath: request.relativePath,
                comment: comment,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            notice = AppLanguage.current.text("파일을 잠갔습니다. 커밋에 성공하면 잠금이 자동으로 해제됩니다.", "The file is locked. A successful commit automatically releases the lock.")
            openFile(request.relativePath, in: project)
            await loadRepositoryLocks()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func openWithoutLock(_ request: DocumentOpenRequest) {
        documentOpenRequest = nil
        guard let project = selectedProject else { return }
        openFile(request.relativePath, in: project)
        notice = AppLanguage.current.text("잠그지 않고 열었습니다. 다른 사용자의 동시 커밋으로 충돌할 수 있습니다.", "Opened without a lock. A concurrent commit by another user may cause a conflict.")
    }

    func loadRepositoryLocks() async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            repositoryLocks = try await client.repositoryLocks(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            updateLockSummary(for: project.id, lockCount: repositoryLocks.count)
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func requestRevert(_ entry: SVNStatusEntry) {
        revertRequest = RevertRequest(entry: entry)
    }

    func confirmRevert() async {
        guard let project = selectedProject, let request = revertRequest else { return }
        revertRequest = nil
        let operationID = beginOperation(.revert(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.revert(at: project.path, relativePath: request.entry.path, credentials: nil)
            selectedPaths.remove(request.entry.path)
            notice = AppLanguage.current.text("로컬 변경을 되돌렸습니다: \(request.entry.path)", "Reverted local changes: \(request.entry.path)")
            await refresh()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func loadFileHistory(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.fileHistory(project.id))
        defer { endOperation(operationID) }
        do {
            fileHistory = try await client.fileLog(
                at: project.path,
                relativePath: relativePath,
                limit: 100,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            fileHistoryPath = relativePath
            isShowingFileHistory = true
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func revealInFinder(_ relativePath: String) {
        guard let project = selectedProject else { return }
        let url = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ relativePath: String) {
        guard let project = selectedProject else { return }
        let path = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath).path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([path as NSString])
        notice = AppLanguage.current.text("파일 경로를 복사했습니다.", "Copied the file path.")
    }

    func unlock(_ lock: SVNLockInfo) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.unlock(
                at: project.path,
                relativePath: lock.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            notice = AppLanguage.current.text("잠금을 해제했습니다.", "The lock was released.")
            await loadRepositoryLocks()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func prepareConflictResolution(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.resolveConflict(project.id))
        defer { endOperation(operationID) }
        do {
            guard let details = try await client.conflictDetails(at: project.path, relativePath: relativePath, credentials: nil) else {
                errorMessage = AppLanguage.current.text("SVN 충돌 상세 정보를 찾지 못했습니다.", "SVN conflict details were not found.")
                return
            }
            activeConflict = SVNConflictDetails(
                path: relativePath,
                type: details.type,
                operation: details.operation,
                previousBaseFile: details.previousBaseFile,
                myFile: details.myFile,
                serverFile: details.serverFile,
                previousRevision: details.previousRevision,
                serverRevision: details.serverRevision
            )
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func resolveActiveConflict(using choice: SVNConflictChoice) async {
        guard let project = selectedProject, let conflict = activeConflict else { return }
        let operationID = beginOperation(.resolveConflict(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try conflictFileService.backup(conflict, projectID: project.id, workingCopyPath: project.path)
            _ = try await client.resolveConflict(at: project.path, relativePath: conflict.path, choice: choice, credentials: nil)
            activeConflict = nil
            notice = AppLanguage.current.text("충돌을 해결 상태로 표시했습니다. diff를 확인한 뒤 커밋하세요.", "The conflict is marked resolved. Review the diff before committing.")
            await refresh()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func preserveConflictVersions() {
        guard let project = selectedProject, let conflict = activeConflict else { return }
        do {
            let files = try conflictFileService.preserveComparableVersions(conflict, workingCopyPath: project.path)
            guard !files.isEmpty else {
                errorMessage = AppLanguage.current.text("보관할 충돌 버전 파일을 찾지 못했습니다.", "No conflict version files were available to preserve.")
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(files)
            notice = AppLanguage.current.text("내 버전과 서버 버전을 원본 옆에 복사했습니다.", "Copied my version and the server version next to the original.")
        } catch {
            errorMessage = localizedError(error)
        }
    }

    func openActiveConflictFile() {
        guard let project = selectedProject, let conflict = activeConflict else { return }
        openFile(conflict.path, in: project)
    }

    func loadHistoryDiff(for revision: String) async {
        guard let project = selectedProject else { return }
        selectedHistoryRevision = revision
        historyDiffContent = .placeholder
        let operationID = beginOperation(.revisionDiff(project.id))
        defer { endOperation(operationID) }
        do {
            let value = try await client.revisionDiff(
                at: project.path,
                revision: revision,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id, selectedHistoryRevision == revision else { return }
            historyDiffContent = value.isEmpty ? .noTextDiff : .text(value)
        } catch {
            if selectedProjectID == project.id { errorMessage = localizedError(error) }
        }
    }

    func loadMoreHistory() async {
        guard let project = selectedProject,
              hasMoreHistory,
              let lastRevision = logs.last?.revision,
              let revision = Int(lastRevision), revision > 1 else { return }
        let operationID = beginOperation(.loadMoreHistory(project.id))
        defer { endOperation(operationID) }
        do {
            let olderLogs = try await client.log(
                at: project.path,
                limit: 50,
                endingAtRevision: String(revision - 1),
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            let existingRevisions = Set(logs.map(\.revision))
            logs.append(contentsOf: olderLogs.filter { !existingRevisions.contains($0.revision) })
            hasMoreHistory = olderLogs.count == 50
        } catch {
            if selectedProjectID == project.id { errorMessage = localizedError(error) }
        }
    }

    func commit(message: String) async -> Bool {
        guard let project = selectedProject, !selectedPaths.isEmpty else { return false }
        let paths = selectedPaths.sorted()
        guard !paths.contains(where: { path in statuses.first(where: { $0.path == path })?.item == .conflicted }) else {
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
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .commit(message: message))
            }
            return false
        }
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

    private func credentials(for project: SVNProject) throws -> SVNCredentials? {
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

    private func handleRemoteError(_ error: Error, project: SVNProject, action: SVNAuthenticationAction) {
        if isKeychainAccessDenied(error) {
            authenticationRequest = SVNAuthenticationRequest(projectID: project.id, action: action)
            notice = authenticationNotice
        } else {
            errorMessage = localizedError(error)
        }
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

    private func localizedError(_ error: Error) -> String {
        guard AppLanguage.current == .english, let svnError = error as? SVNError else {
            return error.localizedDescription
        }
        switch svnError {
        case let .commandFailed(command, message):
            return "\(command) failed: \(message)"
        case .invalidWorkingCopy:
            return "The selected folder is not an SVN local working folder."
        case .malformedResponse:
            return "The SVN response could not be read."
        case .svnExecutableNotFound:
            return "The bundled SVN executable could not be found. Reinstall the app."
        }
    }

    private func openFile(_ relativePath: String, in project: SVNProject) {
        let url = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath)
        guard NSWorkspace.shared.open(url) else {
            errorMessage = AppLanguage.current.text("파일을 열 수 없습니다: \(relativePath)", "Unable to open file: \(relativePath)")
            return
        }
    }

    private func save() {
        // 프로젝트 목록 변경마다 즉시 저장해 앱이 비정상 종료되어도 최근 등록 및
        // 삭제 상태를 최대한 보존합니다. 인코딩 실패 시 기존 저장값은 유지합니다.
        persistence.saveProjects(projects)
    }

    private func updateLocalSummary(for projectID: SVNProject.ID, statuses: [SVNStatusEntry]) {
        var summary = projectSummaries[projectID] ?? ProjectStatusSummary()
        summary.localChangeCount = statuses.count
        summary.conflictCount = statuses.filter { $0.item == .conflicted }.count
        projectSummaries[projectID] = summary
    }

    private func updateRemoteSummary(for projectID: SVNProject.ID, needsUpdate: Bool) {
        var summary = projectSummaries[projectID] ?? ProjectStatusSummary()
        summary.needsUpdate = needsUpdate
        projectSummaries[projectID] = summary
    }

    private func updateLockSummary(for projectID: SVNProject.ID, lockCount: Int) {
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
        statuses = []
        ignoredStatuses = []
        ignoreRules = []
        repositoryLocks = []
        remoteChanges = []
        fileHistory = []
        fileHistoryPath = nil
        showsIgnoredFiles = false
        documentOpenRequest = nil
        activeConflict = nil
        revertRequest = nil
        logs = []
        selectedHistoryRevision = nil
        historyDiffContent = .placeholder
        hasMoreHistory = true
        workingCopyRevision = nil
        isWorkingCopyOutOfDate = nil
        selectedPaths = []
        selectedStatusPath = nil
        diffContent = .placeholder
        notice = nil
        authenticationRequest = nil
    }

    @discardableResult
    private func beginOperation(_ kind: ProjectOperation.Kind) -> UUID {
        let operation = ProjectOperation(kind: kind)
        activeOperations.append(operation)
        return operation.id
    }

    private func endOperation(_ id: UUID) {
        activeOperations.removeAll { $0.id == id }
    }

    /// 요청을 시작했던 프로젝트가 아직 선택되어 있고, 더 최신 refresh가 없을 때만
    /// 비동기 결과를 화면 상태에 반영합니다.
    private func canApplyRefresh(_ requestID: UUID, projectID: SVNProject.ID) -> Bool {
        refreshRequestID == requestID && selectedProjectID == projectID
    }
}
