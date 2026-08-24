import Foundation
import SVNCore

struct DocumentOpenRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let relativePath: String
    let repositoryRelativePath: String
    let existingLock: SVNLockInfo?
}

extension ProjectStore {
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
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            if let existingLock,
               let username = project.username,
               !username.isEmpty,
               existingLock.owner == username {
                notice = AppLanguage.current.localized("ui.opening.a.file.locked.by.you.742588ff")
                openFile(relativePath, in: project)
                return
            }
            let request = DocumentOpenRequest(
                relativePath: relativePath,
                repositoryRelativePath: repositoryRelativePath,
                existingLock: existingLock
            )
            await handleDocumentOpen(request)
        } catch {
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized("ui.lock.information.could.not.be.checked.you.can.op.b80b917b")
            let request = DocumentOpenRequest(
                relativePath: relativePath,
                repositoryRelativePath: repositoryRelativePath,
                existingLock: nil
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
        guard let project = selectedProject else { return }
        documentOpenRequest = nil
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let comment = AppLanguage.current.localized("ui.editing.document.in.svn.kr.5e6ac9cc")
            _ = try await client.lock(
                at: project.path,
                relativePath: request.repositoryRelativePath,
                comment: comment,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized("ui.the.file.is.locked.a.successful.commit.automatic.54dc63dd")
            openFile(request.relativePath, in: project)
            await loadRepositoryLocks()
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
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
        guard let project = selectedProject else { return }
        openFile(request.relativePath, in: project)
        if let existingLock = request.existingLock {
            notice = AppLanguage.current.localized(
                "ui.this.file.is.currently.locked.by.opening.without.ca1f8e9a",
                existingLock.owner
            )
        } else {
            notice = AppLanguage.current.localized("ui.opened.without.a.lock.a.concurrent.commit.by.ano.ff588344")
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
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
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
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized("ui.the.lock.was.released.3aee6b8e")
            await loadRepositoryLocks()
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }
}
