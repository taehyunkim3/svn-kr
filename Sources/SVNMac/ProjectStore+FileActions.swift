import AppKit
import SVNCore

struct CommitDeletionRestoreRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let paths: [String]
}

struct CommitDeletionRestoreFailure: Equatable {
    let path: String
    let message: String
}

struct CommitDeletionRestoreResult: Equatable {
    let restoredPaths: [String]
    let failures: [CommitDeletionRestoreFailure]

    func localizedFailureMessage(_ language: AppLanguage) -> String? {
        guard !failures.isEmpty else { return nil }
        let details = failures
            .map { "\($0.path): \($0.message)" }
            .joined(separator: "\n")
        return language.localized(
            .ui.commit.deletionRestorePartial,
            restoredPaths.count,
            failures.count,
            details
        )
    }
}

extension ProjectStore {
    var selectedCommitDeletionRestorePaths: Set<String> {
        get { recoveryState.selectedCommitDeletionRestorePaths }
        set { recoveryState.selectedCommitDeletionRestorePaths = newValue }
    }

    var commitDeletionRestoreRequest: CommitDeletionRestoreRequest? {
        get { recoveryState.commitDeletionRestoreRequest }
        set { recoveryState.commitDeletionRestoreRequest = newValue }
    }

    var commitDeletionRestoreFailureMessage: String? {
        get { recoveryState.commitDeletionRestoreFailureMessage }
        set { recoveryState.commitDeletionRestoreFailureMessage = newValue }
    }

    func requestRevert(_ entry: SVNStatusEntry) {
        guard let project = selectedProject else { return }
        revertRequest = RevertRequest(projectID: project.id, entry: entry)
    }

    func requestCommitDeletionRestore() {
        guard let project = selectedProject,
              let confirmation = commitConfirmationRequest,
              confirmation.projectID == project.id else { return }
        let presentedPaths = Set(confirmation.serverDeletionEntries.map(\.path))
        let requestedPaths = selectedCommitDeletionRestorePaths.intersection(presentedPaths)
        let eligiblePaths = Self.commitDeletionRestorePaths(
            requestedPaths: requestedPaths,
            statuses: statuses
        )
        guard !eligiblePaths.isEmpty else { return }
        commitDeletionRestoreRequest = CommitDeletionRestoreRequest(
            projectID: project.id,
            paths: eligiblePaths
        )
    }

    /// 변경 사항 목록에서 체크한 삭제 예정 항목만 서버 파일로 복원합니다.
    func requestSelectedDeletionRestore() {
        guard let project = selectedProject else { return }
        let eligiblePaths = Self.commitDeletionRestorePaths(
            requestedPaths: selectedPaths,
            statuses: statuses
        )
        guard !eligiblePaths.isEmpty else { return }
        commitDeletionRestoreRequest = CommitDeletionRestoreRequest(
            projectID: project.id,
            paths: eligiblePaths
        )
    }

    func cancelCommitDeletionRestore() {
        commitDeletionRestoreRequest = nil
    }

    func confirmCommitDeletionRestore(_ request: CommitDeletionRestoreRequest) async {
        guard let project = selectedProject, project.id == request.projectID else {
            commitDeletionRestoreRequest = nil
            return
        }
        commitDeletionRestoreRequest = nil
        let eligiblePaths = Set(Self.commitDeletionRestorePaths(
            requestedPaths: Set(request.paths),
            statuses: statuses
        ))
        let operationID = beginOperation(.revert(project.id))
        defer { endOperation(operationID) }
        var restoredPaths: [String] = []
        var failures: [CommitDeletionRestoreFailure] = []
        for path in request.paths {
            guard eligiblePaths.contains(path) else {
                failures.append(CommitDeletionRestoreFailure(
                    path: path,
                    message: AppLanguage.current.localized(
                        .ui.restore.targetNotDeleted
                    )
                ))
                continue
            }
            do {
                _ = try await client.revert(at: project.path, relativePath: path, credentials: nil)
                restoredPaths.append(path)
            } catch {
                failures.append(CommitDeletionRestoreFailure(
                    path: path,
                    message: localizedError(error)
                ))
            }
        }
        guard selectedProjectID == project.id else { return }
        selectedPaths.subtract(restoredPaths)
        selectedCommitDeletionRestorePaths.removeAll()
        await refreshLocalWorkingCopy()
        guard selectedProjectID == project.id else { return }
        if let confirmation = commitConfirmationRequest,
           confirmation.projectID == project.id {
            commitConfirmationRequest = CommitConfirmationRequest(
                id: confirmation.id,
                projectID: project.id,
                message: confirmation.message,
                selectedPaths: selectedPaths,
                statuses: statuses
            )
        }
        let result = CommitDeletionRestoreResult(
            restoredPaths: restoredPaths,
            failures: failures
        )
        commitDeletionRestoreFailureMessage = result.localizedFailureMessage(.current)
        if failures.isEmpty {
            notice = AppLanguage.current.localized(
                .ui.restored.selectedServerFiles,
                restoredPaths.count
            )
        }
    }

    static func commitDeletionRestorePaths(
        requestedPaths: Set<String>,
        statuses: [SVNStatusEntry]
    ) -> [String] {
        statuses.compactMap { entry in
            guard requestedPaths.contains(entry.path),
                  entry.item == .deleted || entry.canScheduleRepositoryDeletion else { return nil }
            return entry.path
        }
        .sorted()
    }

    func confirmRevert(_ request: RevertRequest) async {
        guard let project = selectedProject, project.id == request.projectID else {
            if revertRequest == request { revertRequest = nil }
            return
        }
        guard revertRequest == nil || revertRequest == request else { return }
        revertRequest = nil
        let requestID = beginRequest(.revert)
        defer { finishRequest(requestID, kind: .revert) }
        let operationID = beginOperation(.revert(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.revert(at: project.path, relativePath: request.entry.path, credentials: nil)
            guard canApplyRequest(
                requestID,
                kind: .revert,
                projectID: request.projectID
            ) else { return }
            selectedPaths.remove(request.entry.path)
            notice = AppLanguage.current.localized(.ui.reverted.localChanges, request.entry.path)
            await refresh()
        } catch {
            guard canApplyRequest(
                requestID,
                kind: .revert,
                projectID: request.projectID
            ) else { return }
            errorMessage = localizedError(error)
        }
    }

    func loadFileHistory(for relativePath: String) async {
        guard let project = selectedProject else { return }
        let request = FileHistoryRequest(
            projectID: project.id,
            relativePath: relativePath
        )
        let requestID = beginRequest(.fileHistory)
        defer { finishRequest(requestID, kind: .fileHistory) }
        let operationID = beginOperation(.fileHistory(project.id))
        defer { endOperation(operationID) }
        do {
            let history = try await client.fileLog(
                at: project.path,
                relativePath: relativePath,
                limit: 100,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard canApplyRequest(
                requestID,
                kind: .fileHistory,
                projectID: request.projectID
            ) else { return }
            fileHistoryRequest = request
            fileHistory = history
            fileHistoryPath = relativePath
            recoveryState.historyRevisionRestoreRequest = nil
            isShowingFileHistory = true
        } catch {
            guard canApplyRequest(
                requestID,
                kind: .fileHistory,
                projectID: request.projectID
            ) else { return }
            errorMessage = localizedError(error)
        }
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
        notice = AppLanguage.current.localized(.ui.copied.theFilePath)
    }
}
