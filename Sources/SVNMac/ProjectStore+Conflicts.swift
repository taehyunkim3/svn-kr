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
            let snapshot = try await client.workingCopySnapshot(at: project.path, credentials: nil)
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            guard let versionedPath = snapshot.resolvedPath(for: relativePath) else {
                throw SVNError.pathNormalizationCollision(
                    paths: [relativePath.precomposedStringWithCanonicalMapping]
                )
            }
            guard let details = try await client.conflictDetails(
                at: project.path,
                relativePath: versionedPath,
                credentials: nil
            ) else {
                throw ConflictFileError.unsupportedType("unknown")
            }
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            let session = try conflictFileService.prepareSession(
                details,
                projectID: projectID,
                workingCopyPath: project.path,
                requestedPath: relativePath,
                versionedPath: versionedPath
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
                relativePath: session.versionedPath,
                choice: choice,
                credentials: nil
            )
            guard canApplyConflictResolution(sessionID, projectID: projectID) else { return }
            activeConflictSession = nil
            await refresh()
            guard canApplyCompletedConflictResolution(sessionID, projectID: projectID) else { return }
            notice = AppLanguage.current.text("충돌을 해결 상태로 표시했습니다. diff를 확인한 뒤 커밋하세요.", "The conflict is marked resolved. Review the diff before committing.")
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

    private func canApplyCompletedConflictResolution(
        _ sessionID: ConflictResolutionSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && activeConflictSession == nil
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }
}
