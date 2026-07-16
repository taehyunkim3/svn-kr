import AppKit
import SVNCore

extension ProjectStore {
    func prepareConflictResolution(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.resolveConflict(project.id))
        defer { endOperation(operationID) }
        do {
            guard let details = try await client.conflictDetails(at: project.path, relativePath: relativePath, credentials: nil) else {
                errorMessage = AppLanguage.current.text("SVN 충돌 상세 정보를 찾지 못했습니다.", "SVN conflict details were not found.")
                return
            }
            activeConflict = SVNConflictDetails(
                path: relativePath,
                type: details.type,
                operation: details.operation,
                previousBaseFile: details.previousBaseFile,
                myFile: details.myFile,
                serverFile: details.serverFile,
                previousRevision: details.previousRevision,
                serverRevision: details.serverRevision
            )
        } catch { errorMessage = localizedError(error) }
    }

    func resolveActiveConflict(using choice: SVNConflictChoice) async {
        guard let project = selectedProject, let conflict = activeConflict else { return }
        let operationID = beginOperation(.resolveConflict(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try conflictFileService.backup(conflict, projectID: project.id, workingCopyPath: project.path)
            _ = try await client.resolveConflict(at: project.path, relativePath: conflict.path, choice: choice, credentials: nil)
            activeConflict = nil
            notice = AppLanguage.current.text("충돌을 해결 상태로 표시했습니다. diff를 확인한 뒤 커밋하세요.", "The conflict is marked resolved. Review the diff before committing.")
            await refresh()
        } catch { errorMessage = localizedError(error) }
    }

    func preserveConflictVersions() {
        guard let project = selectedProject, let conflict = activeConflict else { return }
        do {
            let files = try conflictFileService.preserveComparableVersions(conflict, workingCopyPath: project.path)
            guard !files.isEmpty else {
                errorMessage = AppLanguage.current.text("보관할 충돌 버전 파일을 찾지 못했습니다.", "No conflict version files were available to preserve.")
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(files)
            notice = AppLanguage.current.text("내 버전과 서버 버전을 원본 옆에 복사했습니다.", "Copied my version and the server version next to the original.")
        } catch { errorMessage = localizedError(error) }
    }

    func openActiveConflictFile() {
        guard let project = selectedProject, let conflict = activeConflict else { return }
        openFile(conflict.path, in: project)
    }
}
