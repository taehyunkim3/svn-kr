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
                notice = AppLanguage.current.localized("ui.marked.item.s.for.deletion.commit.to.delete.them.ac2b38ab", result.scheduledPaths.count)
            } else {
                errorMessage = AppLanguage.current.localized(
                    "error.deletion.partial",
                    result.scheduledPaths.count,
                    result.failedPaths.count,
                    result.failedPaths.joined(separator: ", ")
                )
            }
        } catch {
            if selectedProjectID == project.id {
                errorMessage = localizedError(error)
            }
        }
    }

    func commitSelectedChanges(message: String) async -> Bool {
        guard let project = selectedProject, canCommitSelectedPaths else { return false }
        let missingPaths = statuses.compactMap { entry in
            entry.canScheduleRepositoryDeletion && self.selectedPaths.contains(entry.path)
                ? entry.path
                : nil
        }
        guard !missingPaths.isEmpty else { return await commit(message: message) }
        guard await scheduleSelectedMissingDeletions(missingPaths, for: project) else { return false }
        return await commit(message: message)
    }

    private func scheduleSelectedMissingDeletions(
        _ missingPaths: [String],
        for project: SVNProject
    ) async -> Bool {
        let operationID = beginOperation(.delete(project.id))
        defer { endOperation(operationID) }
        do {
            let result = try await client.scheduleDeletion(
                at: project.path,
                paths: missingPaths,
                credentials: credentials(for: project)
            )
            guard selectedProjectID == project.id else { return false }
            await refreshLocalWorkingCopy()
            guard selectedProjectID == project.id else { return false }

            let deletedPaths = Set(statuses.lazy.filter { $0.item == .deleted }.map(\.path))
            let verifiedPaths = result.scheduledPaths.filter(deletedPaths.contains)
            let failedPaths = result.failedPaths + result.scheduledPaths.filter { !deletedPaths.contains($0) }
            selectedPaths.subtract(missingPaths)
            selectedPaths.formUnion(verifiedPaths)
            guard failedPaths.isEmpty else {
                errorMessage = AppLanguage.current.localized(
                    "error.deletion.partial",
                    verifiedPaths.count,
                    failedPaths.count,
                    failedPaths.joined(separator: ", ")
                )
                return false
            }
            return true
        } catch {
            if selectedProjectID == project.id {
                errorMessage = localizedError(error)
            }
            return false
        }
    }
}
