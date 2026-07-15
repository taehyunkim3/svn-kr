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

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [SVNProject] = [] { didSet { save() } }
    @Published var selectedProjectID: SVNProject.ID?
    @Published var statuses: [SVNStatusEntry] = []
    @Published var logs: [SVNLogEntry] = []
    @Published var selectedPaths: Set<String> = []
    @Published var selectedStatusPath: String?
    @Published var diff = "변경 파일을 선택하면 diff가 표시됩니다."
    @Published var isWorking = false
    @Published var isShowingAddRepository = false
    @Published var isShowingCredentials = false
    @Published var notice: String?
    @Published var errorMessage: String?

    private let client = SVNClient()
    private let defaultsKey = "svn-projects-v1"

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
        panel.title = "SVN 작업 복사본 선택"
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
            errorMessage = "이미 등록된 작업 복사본입니다."
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
            errorMessage = error.localizedDescription
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
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeSelectedProject() {
        if let selectedProjectID { try? KeychainStore.deletePassword(for: selectedProjectID) }
        projects.removeAll { $0.id == selectedProjectID }
        selectedProjectID = projects.first?.id
        statuses = []
        logs = []
    }

    func refresh() async {
        guard let project = selectedProject else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let credentials = try credentials(for: project)
            async let newStatuses = client.status(at: project.path, credentials: credentials)
            async let newLogs = client.log(at: project.path, credentials: credentials)
            statuses = try await newStatuses
            logs = try await newLogs
            selectedPaths.formIntersection(Set(statuses.map(\.path)))
            notice = "\(project.name) 새로고침 완료"
        } catch { errorMessage = error.localizedDescription }
    }

    func update() async {
        guard let project = selectedProject else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            notice = try await client.update(at: project.path, credentials: credentials(for: project)).trimmingCharacters(in: .whitespacesAndNewlines)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadDiff(for path: String) async {
        guard let project = selectedProject else { return }
        selectedStatusPath = path
        do {
            let value = try await client.diff(at: project.path, relativePath: path, credentials: credentials(for: project))
            diff = value.isEmpty ? "텍스트 diff가 없습니다. 새 파일 또는 바이너리 파일일 수 있습니다." : value
        } catch { errorMessage = error.localizedDescription }
    }

    func commit(message: String) async -> Bool {
        guard let project = selectedProject, !selectedPaths.isEmpty else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            notice = try await client.commit(at: project.path, paths: selectedPaths.sorted(), message: message, credentials: credentials(for: project))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            selectedPaths.removeAll()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
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
            }
            notice = "\(projects[index].name) 인증 설정 저장 완료"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSavedPassword(for projectID: UUID) -> Bool {
        do {
            try KeychainStore.deletePassword(for: projectID)
            notice = "저장된 비밀번호를 삭제했습니다."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func credentials(for project: SVNProject) throws -> SVNCredentials? {
        guard let username = project.username, !username.isEmpty else { return nil }
        return SVNCredentials(username: username, password: try KeychainStore.password(for: project.id))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
