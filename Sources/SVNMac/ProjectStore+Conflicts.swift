import Foundation
import SVNCore

extension ProjectStore {
    func prepareConflictResolution(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let projectID = project.id
        let requestID = UUID()
        conflictPreparationRequestID = requestID
        let operationID = beginOperation(.resolveConflict(project.id))
        defer {
            endOperation(operationID)
            if conflictPreparationRequestID == requestID {
                conflictPreparationRequestID = nil
            }
        }
        do {
            guard let details = try await client.conflictDetails(
                at: project.path,
                relativePath: relativePath,
                credentials: nil
            ) else {
                throw ConflictFileError.unsupportedType("unknown")
            }
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            let session = try conflictFileService.prepareSession(
                details,
                projectID: projectID,
                workingCopyPath: project.path
            )
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            activeConflictSession = session
        } catch {
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            errorMessage = localizedError(error)
        }
    }

    func openConflictVersion(_ choice: SVNConflictChoice) {
        guard !isResolvingConflict, let session = activeConflictSession else { return }
        let url: URL
        switch choice {
        case .mineFull: url = session.mine.url
        case .theirsFull: url = session.server.url
        case .working: return
        }
        openWorkspaceURL(url)
    }

    func openConflictBackupFolder() {
        guard !isResolvingConflict, let directory = activeConflictSession?.directoryURL else { return }
        openWorkspaceURL(directory)
    }

    func resolveActiveConflict(using choice: SVNConflictChoice) async {
        guard !isResolvingConflict,
              let project = selectedProject,
              let session = activeConflictSession else { return }
        switch choice {
        case .mineFull, .theirsFull:
            break
        case .working:
            return
        }
        let projectID = project.id
        let sessionID = session.id
        resolvingConflictProjectID = projectID
        resolvingConflictSessionID = sessionID
        let operationID = beginOperation(.resolveConflict(projectID))
        defer {
            endOperation(operationID)
            if resolvingConflictProjectID == projectID,
               resolvingConflictSessionID == sessionID {
                resolvingConflictProjectID = nil
                resolvingConflictSessionID = nil
            }
        }
        do {
            _ = try conflictFileService.prepareWorkingFileForResolve(
                for: session,
                choice: choice,
                workingCopyPath: project.path
            )
            _ = try await client.resolveConflict(
                at: project.path,
                relativePath: session.details.path,
                choice: choice,
                credentials: nil
            )
            guard canApplyConflictResolution(sessionID, projectID: projectID) else { return }
            activeConflictSession = nil
            notice = AppLanguage.current.text("충돌을 해결 상태로 표시했습니다. diff를 확인한 뒤 커밋하세요.", "The conflict is marked resolved. Review the diff before committing.")
            await refresh()
        } catch {
            guard canApplyConflictResolution(sessionID, projectID: projectID) else { return }
            errorMessage = localizedError(error)
        }
    }

    private func canApplyConflictPreparation(
        _ requestID: UUID,
        projectID: SVNProject.ID
    ) -> Bool {
        conflictPreparationRequestID == requestID && selectedProjectID == projectID
    }

    private func canApplyConflictResolution(
        _ sessionID: ConflictResolutionSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && activeConflictSession?.id == sessionID
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }
}
