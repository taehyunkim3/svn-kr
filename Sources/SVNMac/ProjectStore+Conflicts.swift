import Foundation
import SVNCore

extension ProjectStore {
    func prepareConflictResolution(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let projectID = project.id
        let operationID = beginOperation(.resolveConflict(project.id))
        defer { endOperation(operationID) }
        do {
            guard let details = try await client.conflictDetails(
                at: project.path,
                relativePath: relativePath,
                credentials: nil
            ) else {
                throw ConflictFileError.unsupportedType("unknown")
            }
            guard selectedProjectID == projectID else { return }
            let session = try conflictFileService.prepareSession(
                details,
                projectID: projectID,
                workingCopyPath: project.path
            )
            guard selectedProjectID == projectID else { return }
            activeConflictSession = session
        } catch {
            guard selectedProjectID == projectID else { return }
            errorMessage = localizedError(error)
        }
    }

    func openConflictVersion(_ choice: SVNConflictChoice) {
        guard let session = activeConflictSession else { return }
        let url: URL
        switch choice {
        case .mineFull: url = session.mine.url
        case .theirsFull: url = session.server.url
        case .working: return
        }
        openWorkspaceURL(url)
    }

    func openConflictBackupFolder() {
        guard let directory = activeConflictSession?.directoryURL else { return }
        openWorkspaceURL(directory)
    }

    func resolveActiveConflict(using choice: SVNConflictChoice) async {
        guard let project = selectedProject, let session = activeConflictSession else { return }
        switch choice {
        case .mineFull, .theirsFull:
            break
        case .working:
            return
        }
        let operationID = beginOperation(.resolveConflict(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.resolveConflict(
                at: project.path,
                relativePath: session.details.path,
                choice: choice,
                credentials: nil
            )
            activeConflictSession = nil
            notice = AppLanguage.current.text("충돌을 해결 상태로 표시했습니다. diff를 확인한 뒤 커밋하세요.", "The conflict is marked resolved. Review the diff before committing.")
            await refresh()
        } catch { errorMessage = localizedError(error) }
    }
}
