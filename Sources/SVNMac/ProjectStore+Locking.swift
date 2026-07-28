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
            documentOpenRequest = DocumentOpenRequest(
                relativePath: relativePath,
                repositoryRelativePath: repositoryRelativePath,
                existingLock: existingLock
            )
        } catch {
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized("ui.lock.information.could.not.be.checked.you.can.op.b80b917b")
            documentOpenRequest = DocumentOpenRequest(
                relativePath: relativePath,
                repositoryRelativePath: repositoryRelativePath,
                existingLock: nil
            )
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

    func openWithoutLock(_ request: DocumentOpenRequest) {
        documentOpenRequest = nil
        guard let project = selectedProject else { return }
        openFile(request.relativePath, in: project)
        notice = AppLanguage.current.localized("ui.opened.without.a.lock.a.concurrent.commit.by.ano.ff588344")
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
