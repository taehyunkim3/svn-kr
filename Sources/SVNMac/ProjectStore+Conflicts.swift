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
            let versionedPathIdentity = SVNPathIdentity(rawPath: versionedPath)
            let statusEntry = snapshot.statuses.first { entry in
                SVNPathIdentity(rawPath: entry.path) == versionedPathIdentity
            }
            let classification = ConflictClassification.classify(
                details: details,
                statusItem: statusEntry?.item,
                propertyState: statusEntry?.propertyState ?? .none
            )
            let wasCanonicallyResolved = Data(relativePath.utf8) != Data(versionedPath.utf8)

            func propertyNames() -> [String] {
                PropertyConflictService().propertyNames(
                    workingCopyPath: project.path,
                    versionedPath: versionedPath,
                    nodeKind: statusEntry?.nodeKind
                )
            }

            func makePropertySession() -> PropertyConflictSession {
                PropertyConflictSession(
                    details: details,
                    requestedPath: relativePath,
                    versionedPath: versionedPath,
                    wasCanonicallyResolved: wasCanonicallyResolved,
                    propertyNames: propertyNames()
                )
            }

            switch classification {
            case let .text(hasPropertyConflict):
                // 내용 충돌이 함께 있으면 항상 내용 충돌 경로로 보냅니다.
                // 이 경로만 mine/server 백업과 작업 파일 복구본을 만듭니다.
                let textSession: ConflictResolutionSession?
                do {
                    textSession = try conflictFileService.prepareSession(
                        ConflictClassification.textConflictDetails(from: details),
                        projectID: projectID,
                        workingCopyPath: project.path,
                        requestedPath: relativePath,
                        versionedPath: versionedPath,
                        hasPropertyConflict: hasPropertyConflict,
                        propertyNames: hasPropertyConflict ? propertyNames() : []
                    )
                } catch ConflictFileError.missingMine, ConflictFileError.missingServer {
                    // 내용 보조 파일이 없으면 비교 화면을 만들 수 없습니다.
                    // 속성 화면으로 보내되, 그 경로도 해결 직전에 작업 파일을 보존합니다.
                    guard hasPropertyConflict else { throw ConflictFileError.missingServer }
                    textSession = nil
                }
                guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
                if let textSession {
                    activeTreeConflictSession = nil
                    recoveryState.propertyConflictSession = nil
                    activeConflictSession = textSession
                } else {
                    activeConflictSession = nil
                    activeTreeConflictSession = nil
                    recoveryState.propertyConflictSession = makePropertySession()
                }
            case .tree:
                let impact = TreeConflictRestoreScan.impact(
                    target: versionedPath,
                    statuses: snapshot.statuses,
                    containedFilePaths: { path in
                        conflictFileService.containedFilePaths(
                            relativePath: path,
                            workingCopyPath: project.path
                        )
                    }
                )
                let session = TreeConflictSession(
                    details: details,
                    requestedPath: relativePath,
                    versionedPath: versionedPath,
                    wasCanonicallyResolved: wasCanonicallyResolved,
                    restoreImpact: impact
                )
                guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
                activeConflictSession = nil
                recoveryState.propertyConflictSession = nil
                activeTreeConflictSession = session
            case .property:
                let session = makePropertySession()
                guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
                activeConflictSession = nil
                activeTreeConflictSession = nil
                recoveryState.propertyConflictSession = session
            case let .unsupported(type):
                throw ConflictFileError.unsupportedType(type)
            }
        } catch {
            guard canApplyConflictPreparation(requestID, projectID: projectID) else { return }
            errorMessage = localizedError(error)
        }
    }

    func resolveActivePropertyConflict(using choice: PropertyConflictResolutionChoice) async {
        guard !isResolvingConflict,
              let project = selectedProject,
              let session = recoveryState.propertyConflictSession else { return }
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
            // `svn resolve`는 같은 경로에 내용 충돌이 남아 있으면 작업 파일까지 교체합니다.
            // 분류가 어긋난 경우에도 되돌릴 수 있도록 실행 전에 복구본을 남깁니다.
            _ = try conflictFileService.preserveSubtree(
                relativePath: session.versionedPath,
                projectID: projectID,
                workingCopyPath: project.path
            )
            _ = try await client.resolveConflict(
                at: project.path,
                relativePath: session.versionedPath,
                choice: choice.svnChoice,
                credentials: nil
            )
            guard canApplyPropertyConflictResolution(sessionID, projectID: projectID) else { return }
            let verifiedSnapshot = try await client.workingCopySnapshot(
                at: project.path,
                credentials: nil
            )
            guard canApplyPropertyConflictResolution(sessionID, projectID: projectID) else { return }
            let verifiedStatuses = try await client.status(at: project.path, credentials: nil)
            guard canApplyPropertyConflictResolution(sessionID, projectID: projectID) else { return }
            try PropertyConflictResolution.verifyResolved(
                path: session.versionedPath,
                in: verifiedSnapshot
            )
            try PropertyConflictResolution.verifyResolved(
                path: session.versionedPath,
                in: verifiedStatuses
            )
            recoveryState.propertyConflictSession = nil
            await refresh()
            guard canApplyCompletedPropertyConflictResolution(sessionID, projectID: projectID) else { return }
            notice = AppLanguage.current.localized("ui.property.conflict.resolved.review.before.commit.7b5e91c4")
        } catch {
            guard canApplyPropertyConflictResolution(sessionID, projectID: projectID) else { return }
            errorMessage = localizedError(error)
        }
    }

    func resolveActiveTreeConflict(using choice: TreeConflictResolutionChoice) async {
        guard !isResolvingConflict,
              let project = selectedProject,
              let session = activeTreeConflictSession else { return }
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
        var subtreeBackup: ConflictSubtreeBackup?
        do {
            switch choice {
            case .keepWorkingState:
                _ = try await client.resolveConflict(
                    at: project.path,
                    relativePath: session.versionedPath,
                    choice: .working,
                    credentials: nil
                )
            case .restoreServerVersion:
                let projectCredentials = try credentials(for: project)
                // `svn revert --depth infinity`는 하위 트리를 통째로 지웁니다.
                // 버전관리되지 않은 파일은 저장소 이력에도 없으므로 먼저 복구본을 만듭니다.
                subtreeBackup = try conflictFileService.preserveSubtree(
                    relativePath: session.versionedPath,
                    projectID: projectID,
                    workingCopyPath: project.path
                )
                guard canApplyTreeConflictResolution(sessionID, projectID: projectID) else { return }
                _ = try await client.revert(
                    at: project.path,
                    relativePath: session.versionedPath,
                    credentials: projectCredentials
                )
                guard canApplyTreeConflictResolution(sessionID, projectID: projectID) else { return }
                _ = try await client.update(
                    at: project.path,
                    credentials: projectCredentials,
                    allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                    allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
                )
            }
            guard canApplyTreeConflictResolution(sessionID, projectID: projectID) else { return }
            let verifiedSnapshot = try await client.workingCopySnapshot(
                at: project.path,
                credentials: nil
            )
            guard canApplyTreeConflictResolution(sessionID, projectID: projectID) else { return }
            let versionedPathIdentity = SVNPathIdentity(rawPath: session.versionedPath)
            guard !verifiedSnapshot.statuses.contains(where: { entry in
                entry.item == .conflicted
                    && SVNPathIdentity(rawPath: entry.path) == versionedPathIdentity
            }) else {
                throw ConflictFileError.conflictResolutionVerificationFailed
            }
            activeTreeConflictSession = nil
            await refresh()
            guard canApplyCompletedTreeConflictResolution(sessionID, projectID: projectID) else { return }
            if let subtreeBackup {
                notice = AppLanguage.current.localized(
                    "ui.tree.conflict.resolved.with.subtree.backup.4c17e9a3",
                    String(subtreeBackup.fileCount),
                    subtreeBackup.directoryURL.path
                )
            } else {
                notice = AppLanguage.current.localized("ui.the.conflict.was.resolved.review.the.file.before.7821924b")
            }
        } catch {
            guard canApplyTreeConflictResolution(sessionID, projectID: projectID) else { return }
            if choice == .restoreServerVersion {
                handleRemoteError(error, project: project, action: .update)
            } else {
                errorMessage = localizedError(error)
            }
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
            if session.hasPropertyConflict {
                try PropertyConflictResolution.verifyResolved(
                    path: session.versionedPath,
                    in: verifiedSnapshot
                )
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

    private func canApplyTreeConflictResolution(
        _ sessionID: TreeConflictSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && activeTreeConflictSession?.id == sessionID
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }

    private func canApplyPropertyConflictResolution(
        _ sessionID: PropertyConflictSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && recoveryState.propertyConflictSession?.id == sessionID
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }

    private func canApplyCompletedConflictResolution(
        _ sessionID: ConflictResolutionSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && activeConflictSession == nil
            && activeTreeConflictSession == nil
            && recoveryState.propertyConflictSession == nil
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }

    private func canApplyCompletedTreeConflictResolution(
        _ sessionID: TreeConflictSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && activeConflictSession == nil
            && activeTreeConflictSession == nil
            && recoveryState.propertyConflictSession == nil
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }

    private func canApplyCompletedPropertyConflictResolution(
        _ sessionID: PropertyConflictSession.ID,
        projectID: SVNProject.ID
    ) -> Bool {
        selectedProjectID == projectID
            && activeConflictSession == nil
            && activeTreeConflictSession == nil
            && recoveryState.propertyConflictSession == nil
            && resolvingConflictSessionID == sessionID
            && resolvingConflictProjectID == projectID
    }
}
