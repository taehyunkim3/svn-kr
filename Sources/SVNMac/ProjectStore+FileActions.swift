import AppKit
import SVNCore

extension ProjectStore {
    func requestRevert(_ entry: SVNStatusEntry) { revertRequest = RevertRequest(entry: entry) }

    func confirmRevert(_ request: RevertRequest) async {
        guard let project = selectedProject else { return }
        revertRequest = nil
        let operationID = beginOperation(.revert(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.revert(at: project.path, relativePath: request.entry.path, credentials: nil)
            selectedPaths.remove(request.entry.path)
            notice = AppLanguage.current.text("로컬 변경을 되돌렸습니다: \(request.entry.path)", "Reverted local changes: \(request.entry.path)")
            await refresh()
        } catch { errorMessage = localizedError(error) }
    }

    func loadFileHistory(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.fileHistory(project.id))
        defer { endOperation(operationID) }
        do {
            fileHistory = try await client.fileLog(
                at: project.path,
                relativePath: relativePath,
                limit: 100,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            fileHistoryPath = relativePath
            isShowingFileHistory = true
        } catch { errorMessage = localizedError(error) }
    }

    func revealInFinder(_ relativePath: String) {
        guard let project = selectedProject else { return }
        let url = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ relativePath: String) {
        guard let project = selectedProject else { return }
        let path = URL(fileURLWithPath: project.path, isDirectory: true).appendingPathComponent(relativePath).path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([path as NSString])
        notice = AppLanguage.current.text("파일 경로를 복사했습니다.", "Copied the file path.")
    }
}
