import Foundation
import SVNCore

extension ProjectStore {
    func prepareToOpen(path relativePath: String) async {
        guard let project = selectedProject else { return }
        guard DocumentFilePolicy.recommendsLock(for: relativePath) else {
            openFile(relativePath, in: project)
            return
        }
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let existingLock = try await client.lockInfo(
                at: project.path,
                relativePath: relativePath,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            documentOpenRequest = DocumentOpenRequest(relativePath: relativePath, existingLock: existingLock)
        } catch { errorMessage = localizedError(error) }
    }

    func lockAndOpen(_ request: DocumentOpenRequest) async {
        guard let project = selectedProject else { return }
        documentOpenRequest = nil
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            let comment = AppLanguage.current.text("SVN Mac에서 문서 편집 중", "Editing document in SVN Mac")
            _ = try await client.lock(
                at: project.path,
                relativePath: request.relativePath,
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

    func loadRepositoryLocks() async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.lock(project.id))
        defer { endOperation(operationID) }
        do {
            repositoryLocks = try await client.repositoryLocks(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            updateLockSummary(for: project.id, lockCount: repositoryLocks.count)
        } catch { errorMessage = localizedError(error) }
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
