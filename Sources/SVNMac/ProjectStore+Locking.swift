import Foundation
import SVNCore

struct DocumentOpenRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let projectID: SVNProject.ID
    let relativePath: String
    let repositoryRelativePath: String
    let existingLock: SVNLockInfo?
    var lockInformationWasUnavailable = false
}

struct ForceUnlockRequest: Identifiable, Equatable {
    let id = UUID()
    let lock: SVNLockInfo
    let originalMessage: String
}

extension ProjectStore {
    var ownedRepositoryLocks: [SVNLockInfo] {
        BulkUnlockPlanner.ownedLocks(
            in: repositoryLocks,
            username: selectedProject?.username
        )
    }

    func prepareExplicitLock(paths: [String]) async {
        guard let project = selectedProject, !paths.isEmpty else { return }
        await loadRepositoryLocks()
        guard selectedProjectID == project.id else { return }

        switch ExplicitLockPlanner.plan(
            paths: paths,
            locks: repositoryLocks,
            username: project.username
        ) {
        case .noAction:
            notice = AppLanguage.current.localized(.ui.all.selectedFilesAlreadyLockedByYou)
        case let .run(command):
            await executeExplicitLock(command, project: project)
        case let .confirmForce(request):
            recoveryState.explicitLockRequest = request
        }
    }

    func forceExplicitLock(_ request: ExplicitLockRequest) async {
        guard recoveryState.explicitLockRequest?.id == request.id,
              let project = selectedProject else { return }
        recoveryState.explicitLockRequest = nil
        await executeExplicitLock(request.forceCommand, project: project)
    }

    func requestBulkUnlock() {
        let locks = ownedRepositoryLocks
        guard !locks.isEmpty else { return }
        recoveryState.bulkUnlockRequest = BulkUnlockRequest(locks: locks)
    }

    func confirmBulkUnlock(_ request: BulkUnlockRequest) async {
        guard recoveryState.bulkUnlockRequest?.id == request.id,
              let project = selectedProject else { return }
        recoveryState.bulkUnlockRequest = nil
        let operationID = beginOperation(.lock(project.id))
        let credentials: SVNCredentials?
        do {
            credentials = try self.credentials(for: project)
        } catch {
            endOperation(operationID)
            errorMessage = localizedError(error)
            return
        }
        let allowsUntrustedCertificate = project.allowsUntrustedServerCertificate == true
        let allowedServerCertificateFailures = allowedServerCertificateFailures(for: project)
        let client = client
        let result = await BulkUnlockExecutor.run(request.locks) { lock in
            _ = try await client.unlock(
                at: project.path,
                relativePath: lock.path,
                force: false,
                credentials: credentials,
                allowUntrustedServerCertificate: allowsUntrustedCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            )
        }
        endOperation(operationID)
        guard selectedProjectID == project.id else { return }

        if result.failures.isEmpty {
            notice = AppLanguage.current.localized(
                .ui.bulk.unlockCompleted,
                result.releasedPaths.count
            )
        } else {
            recoveryState.bulkUnlockResult = result
        }
        await loadRepositoryLocks()
    }

    private func executeExplicitLock(
        _ command: ExplicitLockCommand,
        project: SVNProject
    ) async {
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let comment = AppLanguage.current.localized(.ui.editing.documentInSvnKr)
            if let multiplePathClient = client as? any MultiplePathLockServing {
                try await ExplicitLockCommandRunner(client: multiplePathClient).run(
                    command,
                    workingCopyPath: project.path,
                    comment: comment,
                    credentials: credentials(for: project),
                    allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                    allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
                )
            } else if command.force {
                throw ExplicitLockExecutionError.forceUnsupported
            } else {
                for path in command.paths {
                    _ = try await client.lock(
                        at: project.path,
                        relativePath: path,
                        comment: comment,
                        credentials: credentials(for: project),
                        allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                        allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
                    )
                }
            }
            guard selectedProjectID == project.id else { return }
            recoveryState.explicitLockRequest = nil
            notice = AppLanguage.current.localized(
                .ui.explicit.lockCompleted,
                command.paths.count
            )
            await loadRepositoryLocks()
        } catch {
            guard selectedProjectID == project.id else { return }
            if !command.force {
                await loadRepositoryLocks()
                guard selectedProjectID == project.id else { return }
                if case let .confirmForce(request) = ExplicitLockPlanner.plan(
                    paths: command.paths,
                    locks: repositoryLocks,
                    username: project.username
                ) {
                    recoveryState.explicitLockRequest = request
                    errorMessage = nil
                    return
                }
            }
            recoveryState.explicitLockRequest = nil
            if !offerWorkingCopyCleanup(for: error, projectID: project.id) {
                errorMessage = localizedError(error)
            }
        }
    }

    func prepareToOpen(
        path relativePath: String,
        repositoryPath: String? = nil,
        isVersioned: Bool = true,
        isRegularFile: Bool = true
    ) async {
        guard let project = selectedProject else { return }
        guard isVersioned, isRegularFile else {
            openFile(relativePath, in: project)
            return
        }
        let repositoryRelativePath = repositoryPath ?? relativePath
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let existingLock = try await client.lockInfo(
                at: project.path,
                relativePath: repositoryRelativePath,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id else { return }
            if let existingLock,
               let username = project.username,
               !username.isEmpty,
               existingLock.owner == username {
                notice = AppLanguage.current.localized(.ui.opening.aFileLockedByYou)
                openFile(relativePath, in: project)
                return
            }
            let request = DocumentOpenRequest(
                projectID: project.id,
                relativePath: relativePath,
                repositoryRelativePath: repositoryRelativePath,
                existingLock: existingLock
            )
            await handleDocumentOpen(request)
        } catch {
            guard selectedProjectID == project.id else { return }
            if offerWorkingCopyCleanup(for: error, projectID: project.id) { return }
            notice = AppLanguage.current.localized(.ui.lock.informationCouldNotBeCheckedYouCanOp)
            let request = DocumentOpenRequest(
                projectID: project.id,
                relativePath: relativePath,
                repositoryRelativePath: repositoryRelativePath,
                existingLock: nil,
                lockInformationWasUnavailable: true
            )
            switch AppSettings.documentOpenLockPolicy(in: settingsDefaults) {
            case .askEveryTime:
                documentOpenRequest = request
            case .alwaysOpenWithoutLock:
                openFile(relativePath, in: project)
            case .alwaysLockAndOpen:
                await lockAndOpen(request)
            }
        }
    }

    private func handleDocumentOpen(_ request: DocumentOpenRequest) async {
        switch AppSettings.documentOpenLockPolicy(in: settingsDefaults) {
        case .askEveryTime:
            documentOpenRequest = request
        case .alwaysOpenWithoutLock:
            openWithoutLock(request)
        case .alwaysLockAndOpen:
            if request.existingLock == nil {
                await lockAndOpen(request)
            } else {
                openWithoutLock(request)
            }
        }
    }

    func lockAndOpen(_ request: DocumentOpenRequest) async {
        guard let project = selectedProject, project.id == request.projectID else { return }
        documentOpenRequest = nil
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let comment = AppLanguage.current.localized(.ui.editing.documentInSvnKr)
            _ = try await client.lock(
                at: project.path,
                relativePath: request.repositoryRelativePath,
                comment: comment,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized(.ui.the.fileIsLockedASuccessfulCommitAutomatic)
            openFile(request.relativePath, in: project)
            await loadRepositoryLocks()
        } catch {
            guard selectedProjectID == project.id else { return }
            if !offerWorkingCopyCleanup(for: error, projectID: project.id) {
                errorMessage = localizedError(error)
            }
        }
    }

    func openWithoutLock(
        _ request: DocumentOpenRequest,
        rememberingChoice: Bool = false
    ) {
        documentOpenRequest = nil
        if rememberingChoice {
            AppSettings.setDocumentOpenLockPolicy(
                .alwaysOpenWithoutLock,
                in: settingsDefaults
            )
        }
        guard let project = selectedProject, project.id == request.projectID else { return }
        openFile(request.relativePath, in: project)
        if let existingLock = request.existingLock {
            notice = AppLanguage.current.localized(
                .ui.this.fileIsCurrentlyLockedByOpeningWithout,
                existingLock.owner
            )
        } else {
            notice = AppLanguage.current.localized(.ui.opened.withoutALockAConcurrentCommitByAno)
        }
    }

    func loadRepositoryLocks(
        errorPolicy: RefreshErrorPolicy = .standalone
    ) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return }
        let requestID = beginRequest(.repositoryLocks)
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let locks = try await client.repositoryLocks(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard canApplyRequest(requestID, kind: .repositoryLocks, projectID: project.id) else { return }
            repositoryLocks = locks
            updateLockSummary(for: project.id, lockCount: locks.count)
        } catch {
            guard canApplyRequest(requestID, kind: .repositoryLocks, projectID: project.id) else { return }
            publishRefreshError(error, projectID: project.id, policy: errorPolicy)
        }
    }

    func unlock(_ lock: SVNLockInfo) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.unlock(
                at: project.path,
                relativePath: lock.path,
                force: false,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized(.ui.the.lockWasReleased)
            forceUnlockRequest = nil
            await loadRepositoryLocks()
        } catch {
            guard selectedProjectID == project.id else { return }
            if SVNErrorLocalization.suggestsForceUnlock(error) {
                forceUnlockRequest = ForceUnlockRequest(
                    lock: lock,
                    originalMessage: SVNErrorLocalization.diagnosticDetails(for: error)
                )
                errorMessage = nil
            } else if !offerWorkingCopyCleanup(for: error, projectID: project.id) {
                errorMessage = localizedError(error)
            }
        }
    }

    func forceUnlock(_ request: ForceUnlockRequest) async {
        guard forceUnlockRequest?.id == request.id,
              let project = selectedProject else { return }
        forceUnlockRequest = nil
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.unlock(
                at: project.path,
                relativePath: request.lock.path,
                force: true,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id else { return }
            forceUnlockRequest = nil
            notice = AppLanguage.current.localized(.ui.the.lockWasForceReleased)
            await loadRepositoryLocks()
        } catch {
            guard selectedProjectID == project.id else { return }
            forceUnlockRequest = nil
            if !offerWorkingCopyCleanup(for: error, projectID: project.id) {
                errorMessage = localizedError(error)
            }
        }
    }
}
