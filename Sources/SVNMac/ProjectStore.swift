import AppKit
import Foundation
import SVNCore

struct SVNProject: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
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
            async let newStatuses = client.status(at: project.path)
            async let newLogs = client.log(at: project.path)
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
            notice = try await client.update(at: project.path).trimmingCharacters(in: .whitespacesAndNewlines)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadDiff(for path: String) async {
        guard let project = selectedProject else { return }
        selectedStatusPath = path
        do {
            let value = try await client.diff(at: project.path, relativePath: path)
            diff = value.isEmpty ? "텍스트 diff가 없습니다. 새 파일 또는 바이너리 파일일 수 있습니다." : value
        } catch { errorMessage = error.localizedDescription }
    }

    func commit(message: String) async -> Bool {
        guard let project = selectedProject, !selectedPaths.isEmpty else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            notice = try await client.commit(at: project.path, paths: selectedPaths.sorted(), message: message)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            selectedPaths.removeAll()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
