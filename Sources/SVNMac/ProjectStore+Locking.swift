import Foundation
import SVNCore

struct DocumentOpenRequest: Identifiable, Equatable {
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
                notice = AppLanguage.current.text(
                    "내가 잠근 파일을 엽니다.",
                    "Opening a file locked by you."
                )
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
            notice = AppLanguage.current.text(
                "잠금 정보를 확인하지 못했습니다. 잠그지 않고 파일을 열 수 있습니다.",
                "Lock information could not be checked. You can open the file without locking it."
            )
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
            let comment = AppLanguage.current.text("SVN KR에서 문서 편집 중", "Editing document in SVN KR")
            _ = try await client.lock(
                at: project.path,
                relativePath: request.repositoryRelativePath,
                comment: comment,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            notice = AppLanguage.current.text("파일을 잠갔습니다. 커밋에 성공하면 잠금이 자동으로 해제됩니다.", "The file is locked. A successful commit automatically releases the lock.")
            openFile(request.relativePath, in: project)
            await loadRepositoryLocks()
        } catch { errorMessage = localizedError(error) }
    }

    func openWithoutLock(_ request: DocumentOpenRequest) {
        documentOpenRequest = nil
        guard let project = selectedProject else { return }
        openFile(request.relativePath, in: project)
        notice = AppLanguage.current.text("잠그지 않고 열었습니다. 다른 사용자의 동시 커밋으로 충돌할 수 있습니다.", "Opened without a lock. A concurrent commit by another user may cause a conflict.")
    }

    func loadRepositoryLocks(
        errorPolicy: RefreshErrorPolicy = .standalone
    ) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return }
        let requestID = UUID()
        repositoryLocksRequestID = requestID
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let locks = try await client.repositoryLocks(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard repositoryLocksRequestID == requestID,
                  selectedProjectID == project.id else { return }
            repositoryLocks = locks
            updateLockSummary(for: project.id, lockCount: locks.count)
        } catch {
            guard repositoryLocksRequestID == requestID,
                  selectedProjectID == project.id else { return }
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
            notice = AppLanguage.current.text("잠금을 해제했습니다.", "The lock was released.")
            await loadRepositoryLocks()
        } catch { errorMessage = localizedError(error) }
    }
}
