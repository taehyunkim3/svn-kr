import AppKit
import Foundation
import SVNCore

struct SVNProject: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var username: String?

    init(id: UUID = UUID(), name: String, path: String, username: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.username = username
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
    @Published var projects: [SVNProject] = [] { didSet { save() } }
    @Published var selectedProjectID: SVNProject.ID?
    @Published var statuses: [SVNStatusEntry] = []
    @Published var logs: [SVNLogEntry] = []
    @Published var workingCopyRevision: String?
    @Published var selectedPaths: Set<String> = []
    @Published var selectedStatusPath: String?
    @Published var diff = AppLanguage.current.text("변경 파일을 선택하면 diff가 표시됩니다.", "Select a changed file to view its diff.")
    @Published var isWorking = false
    @Published var isShowingAddRepository = false
    @Published var isShowingCredentials = false
    @Published var authenticationRequest: SVNAuthenticationRequest?
    @Published var lastCompletedCommitMessage: String?
    @Published var notice: String?
    @Published var errorMessage: String?

    private let client = SVNClient()
    private let defaultsKey = "svn-projects-v1"
    private var sessionPasswords: [SVNProject.ID: String] = [:]

    var selectedProject: SVNProject? {
        projects.first { $0.id == selectedProjectID }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([SVNProject].self, from: data) {
            projects = saved
            selectedProjectID = saved.first?.id
        }
    }

    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.current.text("SVN 로컬 작업 폴더 선택", "Choose SVN Local Working Folders")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addProject(url) }
    }

    func checkout(repositoryURL: String, destinationPath: String, username: String, password: String) async -> Bool {
        let repositoryURL = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationPath = (destinationPath as NSString).expandingTildeInPath
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryURL.isEmpty, !destinationPath.isEmpty else { return false }
        guard !projects.contains(where: { $0.path == destinationPath }) else {
            errorMessage = AppLanguage.current.text("이미 등록된 로컬 작업 폴더입니다.", "This local working folder is already registered.")
            return false
        }

        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let id = UUID()
            let credentials = username.isEmpty ? nil : SVNCredentials(username: username, password: password.isEmpty ? nil : password)
            notice = try await client.checkout(repositoryURL: repositoryURL, destinationPath: destinationPath, credentials: credentials)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
            let project = SVNProject(id: id, name: destination.lastPathComponent, path: destination.path, username: username.isEmpty ? nil : username)
            if !password.isEmpty { try KeychainStore.setPassword(password, for: id) }
            projects.append(project)
            selectedProjectID = project.id
            await refresh()
            return true
        } catch {
            errorMessage = localizedError(error)
            return false
        }
    }

    func addProject(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !projects.contains(where: { $0.path == path }) else { return }
        Task {
            do {
                try await client.validateWorkingCopy(at: path)
                let project = SVNProject(name: url.lastPathComponent, path: path)
                projects.append(project)
                selectedProjectID = project.id
                await refresh()
            } catch { errorMessage = localizedError(error) }
        }
    }

    func removeSelectedProject() {
        if let selectedProjectID {
            sessionPasswords[selectedProjectID] = nil
            try? KeychainStore.deletePassword(for: selectedProjectID)
        }
        projects.removeAll { $0.id == selectedProjectID }
        selectedProjectID = projects.first?.id
        statuses = []
        logs = []
        workingCopyRevision = nil
    }

    func refresh() async {
        guard let project = selectedProject else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            async let newStatuses = client.status(at: project.path)
            async let newWorkingCopyRevision = client.workingCopyRevision(at: project.path)
            let (statuses, workingCopyRevision) = try await (newStatuses, newWorkingCopyRevision)
            self.statuses = statuses
            self.workingCopyRevision = workingCopyRevision
            selectedPaths.formIntersection(Set(statuses.map(\.path)))
            notice = AppLanguage.current.text("\(project.name) 로컬 변경 사항 확인 완료", "\(project.name) local changes refreshed")
        } catch {
            errorMessage = localizedError(error)
            return
        }

        do {
            logs = try await client.log(at: project.path, credentials: credentials(for: project))
            notice = AppLanguage.current.text("\(project.name) 새로고침 완료", "\(project.name) refreshed")
        } catch {
            handleRemoteError(error, project: project, action: .refreshHistory)
        }
    }

    func update() async {
        guard let project = selectedProject else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            notice = try await client.update(at: project.path, credentials: credentials(for: project)).trimmingCharacters(in: .whitespacesAndNewlines)
            await refresh()
        } catch {
            handleRemoteError(error, project: project, action: .update)
        }
    }

    func loadDiff(for path: String) async {
        guard let project = selectedProject else { return }
        selectedStatusPath = path
        do {
            let value = try await client.diff(at: project.path, relativePath: path)
            diff = value.isEmpty
                ? AppLanguage.current.text("텍스트 diff가 없습니다. 새 파일 또는 바이너리 파일일 수 있습니다.", "No text diff is available. This may be a new or binary file.")
                : value
        } catch { errorMessage = localizedError(error) }
    }

    func commit(message: String) async -> Bool {
        guard let project = selectedProject, !selectedPaths.isEmpty else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            notice = try await client.commit(at: project.path, paths: selectedPaths.sorted(), message: message, credentials: credentials(for: project))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            selectedPaths.removeAll()
            lastCompletedCommitMessage = message
            await refresh()
            return true
        } catch {
            handleRemoteError(error, project: project, action: .commit(message: message))
            return false
        }
    }

    func hasSavedPassword(for projectID: UUID) -> Bool {
        (try? KeychainStore.password(for: projectID)) != nil
    }

    func saveCredentials(for projectID: UUID, username: String, newPassword: String) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        do {
            let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            projects[index].username = username.isEmpty ? nil : username
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
        isWorking = true
        defer { isWorking = false }
        do {
            logs = try await client.log(at: project.path, credentials: credentials(for: project))
            notice = AppLanguage.current.text("\(project.name) 커밋 기록 확인 완료", "\(project.name) history refreshed")
        } catch {
            handleRemoteError(error, project: project, action: .refreshHistory)
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

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
