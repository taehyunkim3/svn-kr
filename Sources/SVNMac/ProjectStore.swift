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
    @Published var logs: [SVNLogEntry] = []
    @Published var workingCopyRevision: String?
    @Published var isWorkingCopyOutOfDate: Bool?
    @Published var selectedPaths: Set<String> = []
    @Published var selectedStatusPath: String?
    @Published var diffContent: DiffContent = .placeholder
    @Published private(set) var isWorking = false
    @Published var isShowingAddRepository = false
    @Published var isShowingCredentials = false
    @Published var authenticationRequest: SVNAuthenticationRequest?
    @Published var lastCompletedCommitMessage: String?
    @Published var notice: String?
    @Published var errorMessage: String?

    // MARK: - 외부 서비스와 비동기 작업 추적

    private let client = SVNClient()
    private let defaultsKey = "svn-projects-v1"
    private var sessionPasswords: [SVNProject.ID: String] = [:]
    private var accessedProjectURLs: [SVNProject.ID: URL] = [:]
    /// update가 끝난 뒤 refresh가 이어지는 것처럼 작업이 중첩될 수 있으므로
    /// Bool을 직접 켜고 끄지 않고 실행 중인 작업 수로 busy 상태를 계산합니다.
    private var activeOperationCount = 0
    /// 새 refresh가 시작되거나 프로젝트가 바뀌면 이전 결과를 폐기하기 위한 토큰입니다.
    private var refreshRequestID: UUID?
    /// 빠르게 여러 파일을 선택했을 때 늦게 끝난 이전 diff가 덮어쓰지 않게 합니다.
    private var diffRequestID: UUID?

    var selectedProject: SVNProject? {
        projects.first { $0.id == selectedProjectID }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([SVNProject].self, from: data) {
            projects = saved
            restoreProjectAccess()
            selectedProjectID = saved.first?.id
        }
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
        beginOperation()
        defer { endOperation() }

        // 체크아웃은 파일 시스템을 실제로 변경합니다. 체크아웃 성공 이후의
        // Keychain 저장 실패까지 전체 실패로 취급하면, 화면에는 실패라고 나오지만
        // 디스크에는 파일이 남는 모호한 상태가 됩니다. 그래서 경계를 둘로 나눕니다.
        let id = UUID()
        let bookmarkData: Data
        let checkoutNotice: String
        do {
            bookmarkData = try makeBookmark(for: destination)
            beginAccessing(destination, for: id)
            let credentials = username.isEmpty ? nil : SVNCredentials(username: username, password: password.isEmpty ? nil : password)
            checkoutNotice = try await client.checkout(
                repositoryURL: repositoryURL,
                destinationPath: destinationPath,
                credentials: credentials,
                allowUntrustedServerCertificate: allowsUntrustedServerCertificate
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            endAccessingProject(at: destinationURL.standardizedFileURL)
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
                try KeychainStore.setPassword(password, for: id)
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
            beginOperation()
            defer { endOperation() }
            let projectID = UUID()
            do {
                let bookmarkData = try makeBookmark(for: url)
                beginAccessing(url, for: projectID)
                try await client.validateWorkingCopy(at: path)
                let project = SVNProject(id: projectID, name: url.lastPathComponent, path: path, bookmarkData: bookmarkData)
                projects.append(project)
                selectedProjectID = project.id
                await refresh()
            } catch {
                endAccessingProject(id: projectID)
                errorMessage = localizedError(error)
            }
        }
    }

    func removeSelectedProject() {
        if let selectedProjectID {
            sessionPasswords[selectedProjectID] = nil
            try? KeychainStore.deletePassword(for: selectedProjectID)
            endAccessingProject(id: selectedProjectID)
        }
        projects.removeAll { $0.id == selectedProjectID }
        selectedProjectID = projects.first?.id
    }

    // MARK: - SVN 작업

    func refresh() async {
        guard let project = selectedProject else { return }
        let requestID = UUID()
        refreshRequestID = requestID
        beginOperation()
        defer { endOperation() }
        isWorkingCopyOutOfDate = nil
        do {
            async let newStatuses = client.status(at: project.path)
            async let newWorkingCopyRevision = client.workingCopyRevision(at: project.path)
            let (statuses, workingCopyRevision) = try await (newStatuses, newWorkingCopyRevision)
            guard canApplyRefresh(requestID, projectID: project.id) else { return }
            self.statuses = statuses
            self.workingCopyRevision = workingCopyRevision
            selectedPaths.formIntersection(Set(statuses.map(\.path)))
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
            self.isWorkingCopyOutOfDate = isWorkingCopyOutOfDate
            notice = AppLanguage.current.text("\(project.name) 새로고침 완료", "\(project.name) refreshed")
        } catch {
            if canApplyRefresh(requestID, projectID: project.id) {
                handleRemoteError(error, project: project, action: .refreshHistory)
            }
        }
    }

    func update() async {
        guard let project = selectedProject else { return }
        beginOperation()
        defer { endOperation() }
        do {
            let result = try await client.update(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedProjectID == project.id else { return }
            notice = result
            await refresh()
        } catch {
            if selectedProjectID == project.id {
                handleRemoteError(error, project: project, action: .update)
            }
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
            let value = try await client.diff(at: project.path, relativePath: path)
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
        beginOperation()
        defer { endOperation() }
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
        (try? KeychainStore.password(for: projectID)) != nil
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
                try KeychainStore.setPassword(newPassword, for: projectID)
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
            try KeychainStore.deletePassword(for: projectID)
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
                try KeychainStore.setPassword(password, for: request.projectID)
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
        let password = try KeychainStore.password(for: project.id)
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
        beginOperation()
        defer { endOperation() }
        do {
            let newLogs = try await client.log(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            logs = newLogs
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

    // MARK: - Security-scoped bookmark 관리

    private func makeBookmark(for url: URL) throws -> Data {
        try url.standardizedFileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func restoreProjectAccess() {
        for index in projects.indices {
            guard let bookmarkData = projects[index].bookmarkData else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            let standardizedURL = url.standardizedFileURL
            projects[index].path = standardizedURL.path
            if isStale, let refreshedBookmark = try? makeBookmark(for: standardizedURL) {
                projects[index].bookmarkData = refreshedBookmark
            }
            beginAccessing(standardizedURL, for: projects[index].id)
        }
    }

    private func beginAccessing(_ url: URL, for projectID: SVNProject.ID) {
        guard accessedProjectURLs[projectID] == nil else { return }
        _ = url.startAccessingSecurityScopedResource()
        accessedProjectURLs[projectID] = url
    }

    private func endAccessingProject(id: SVNProject.ID) {
        guard let url = accessedProjectURLs.removeValue(forKey: id) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func endAccessingProject(at url: URL) {
        guard let entry = accessedProjectURLs.first(where: { $0.value == url }) else { return }
        endAccessingProject(id: entry.key)
    }

    private func save() {
        // 프로젝트 목록 변경마다 즉시 저장해 앱이 비정상 종료되어도 최근 등록 및
        // 삭제 상태를 최대한 보존합니다. 인코딩 실패 시 기존 저장값은 유지합니다.
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - 화면 상태와 작업 수명 관리

    /// 프로젝트가 바뀔 때 이전 프로젝트의 화면 상태가 잠깐 보이지 않도록 관련
    /// 상태를 한곳에서 초기화합니다. 진행 중이던 요청 토큰도 폐기합니다.
    private func resetSelectedProjectState() {
        refreshRequestID = nil
        diffRequestID = nil
        statuses = []
        logs = []
        workingCopyRevision = nil
        isWorkingCopyOutOfDate = nil
        selectedPaths = []
        selectedStatusPath = nil
        diffContent = .placeholder
        notice = nil
        authenticationRequest = nil
    }

    private func beginOperation() {
        activeOperationCount += 1
        isWorking = true
    }

    private func endOperation() {
        activeOperationCount = max(0, activeOperationCount - 1)
        isWorking = activeOperationCount > 0
    }

    /// 요청을 시작했던 프로젝트가 아직 선택되어 있고, 더 최신 refresh가 없을 때만
    /// 비동기 결과를 화면 상태에 반영합니다.
    private func canApplyRefresh(_ requestID: UUID, projectID: SVNProject.ID) -> Bool {
        refreshRequestID == requestID && selectedProjectID == projectID
    }
}
