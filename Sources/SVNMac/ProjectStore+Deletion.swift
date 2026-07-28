import Foundation
import SVNCore

struct DeletionRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let entries: [SVNStatusEntry]

    var containsDirectory: Bool {
        entries.contains { $0.nodeKind == .directory }
    }
}

extension ProjectStore {
    var scheduledDeletionCount: Int {
        selectedPaths.count { path in
            statuses.first { $0.path == path }?.item == .deleted
        }
    }

    func requestDeletion(_ entry: SVNStatusEntry) {
        requestDeletion([entry])
    }

    func requestDeletion(_ entries: [SVNStatusEntry]) {
        guard let project = selectedProject else { return }
        let eligibleEntries = entries.filter(\.canScheduleRepositoryDeletion)
        guard !eligibleEntries.isEmpty else { return }
        deletionRequest = DeletionRequest(projectID: project.id, entries: eligibleEntries)
    }

    func cancelDeletion() {
        deletionRequest = nil
    }

    func confirmDeletion(_ request: DeletionRequest) async {
        guard let project = selectedProject, project.id == request.projectID else {
            deletionRequest = nil
            return
        }
        deletionRequest = nil
        let paths = request.entries.map(\.path)
        let operationID = beginOperation(.delete(project.id))
        defer { endOperation(operationID) }
        do {
            let result = try await client.scheduleDeletion(
                at: project.path,
                paths: paths,
                credentials: credentials(for: project)
            )
            guard selectedProjectID == project.id else { return }
            await refreshLocalWorkingCopy()
            let deletedPaths = Set(statuses.lazy.filter { $0.item == .deleted }.map(\.path))
            selectedPaths.formUnion(result.scheduledPaths.filter(deletedPaths.contains))
            if result.failedPaths.isEmpty {
                notice = AppLanguage.current.text(
                    "\(result.scheduledPaths.count)개 항목을 삭제 예정으로 표시했습니다. 커밋하면 저장소에서 삭제됩니다.",
                    "Marked \(result.scheduledPaths.count) item(s) for deletion. Commit to delete them from the repository."
                )
            } else {
                errorMessage = AppLanguage.current.text(
                    "\(result.scheduledPaths.count)개는 삭제 예정으로 전환했고, \(result.failedPaths.count)개는 전환하지 못했습니다: \(result.failedPaths.joined(separator: ", "))",
                    "\(result.scheduledPaths.count) item(s) were marked for deletion, but \(result.failedPaths.count) failed: \(result.failedPaths.joined(separator: ", "))"
                )
            }
        } catch {
            if selectedProjectID == project.id {
                errorMessage = localizedError(error)
            }
        }
    }
}
