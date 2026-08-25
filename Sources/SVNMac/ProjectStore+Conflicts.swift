import Foundation
import SVNCore

extension ProjectStore {
    func prepareConflictResolution(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let projectID = project.id
        let requestID = beginRequest(.conflictPreparation)
        let operationID = beginOperation(.resolveConflict(project.id))
        defer {
            endOperation(operationID)
            finishRequest(requestID, kind: .conflictPreparation)
        }
        do {
            let snapshot = try await client.workingCopySnapshot(at: project.path, credentials: nil)
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            guard let resolvedPath = snapshot.resolvedPath(for: relativePath) else {
                throw SVNError.pathNormalizationCollision(
                    paths: [relativePath.precomposedStringWithCanonicalMapping]
                )
            }
            guard let (details, versionedPath) = try await conflictDetails(
                at: project.path,
                resolvedPath: resolvedPath,
                requestID: requestID,
                projectID: projectID
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

    /// 계약 스텁: 트리 충돌 해결 구현 작업에서 실제 동작으로 대체합니다.
    /// keepWorkingState는 `svn resolve --accept working`,
    /// restoreServerVersion은 `svn revert` 후 `svn update`에 해당합니다.
    func resolveActiveTreeConflict(using _: TreeConflictResolutionChoice) async {}

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
        case .mineFull, .theirsFull, .working:
            break
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
            let verifiedSnapshot = try await client.workingCopySnapshot(
                at: project.path,
                credentials: nil
            )
            guard canApplyConflictResolution(sessionID, projectID: projectID) else { return }
            let versionedPathIdentity = SVNPathIdentity(rawPath: session.versionedPath)
            guard !verifiedSnapshot.statuses.contains(where: { entry in
                entry.item == .conflicted
                    && SVNPathIdentity(rawPath: entry.path) == versionedPathIdentity
            }) else {
                throw ConflictFileError.conflictResolutionVerificationFailed
            }
            activeConflictSession = nil
            await refresh()
            guard canApplyCompletedConflictResolution(sessionID, projectID: projectID) else { return }
            notice = AppLanguage.current.localized("ui.the.conflict.was.resolved.review.the.file.before.7821924b")
        } catch {
            guard canApplyConflictResolution(sessionID, projectID: projectID) else { return }
            errorMessage = localizedError(error)
        }
    }

    private func canApplyConflictPreparation(
        _ requestID: UUID,
        projectID: SVNProject.ID
    ) -> Bool {
        canApplyRequest(requestID, kind: .conflictPreparation, projectID: projectID)
    }

    private func conflictDetails(
        at projectPath: String,
        resolvedPath: String,
        requestID: UUID,
        projectID: SVNProject.ID
    ) async throws -> (SVNConflictDetails, String)? {
        let candidates = distinctRawPaths([
            resolvedPath.precomposedStringWithCanonicalMapping,
            resolvedPath,
        ])
        var lastError: Error?
        for candidate in candidates {
            do {
                let details = try await client.conflictDetails(
                    at: projectPath,
                    relativePath: candidate,
                    credentials: nil
                )
                guard canApplyConflictPreparation(requestID, projectID: projectID) else { return nil }
                if let details { return (details, candidate) }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private func distinctRawPaths(_ paths: [String]) -> [String] {
        var seen: Set<Data> = []
        return paths.filter { seen.insert(Data($0.utf8)).inserted }
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
