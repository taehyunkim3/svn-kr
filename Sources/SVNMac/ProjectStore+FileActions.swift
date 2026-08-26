import AppKit
import SVNCore

/// 폴더 되돌리기가 지울 하위 항목입니다.
/// `svn revert --depth infinity`는 대상 아래를 통째로 되돌리므로,
/// 확인창이 개수만이 아니라 경로를 보여줄 수 있도록 스캔 결과를 붙여 둡니다.
/// 트리 충돌 되돌리기와 같은 위험 분류를 씁니다.
struct RevertImpactContext: Equatable {
    let requestID: RevertRequest.ID
    let impact: TreeConflictRestoreImpact
}

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
            .ui.file.restoredButFailed,
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

    var revertImpactContext: RevertImpactContext? {
        get { recoveryState.revertImpactContext }
        set { recoveryState.revertImpactContext = newValue }
    }

    /// 확인창이 보여줄 하위 항목입니다. 요청이 바뀌면 이전 결과를 쓰지 않습니다.
    func revertImpact(for request: RevertRequest) -> TreeConflictRestoreImpact? {
        guard let context = revertImpactContext, context.requestID == request.id else { return nil }
        return context.impact
    }

    func requestRevert(_ entry: SVNStatusEntry) {
        guard let project = selectedProject else { return }
        let request = RevertRequest(projectID: project.id, entry: entry)
        // 파일 하나를 되돌리면 확인창의 경로가 곧 사라지는 것 전부입니다.
        // 폴더는 하위 항목이 함께 사라지므로 목록을 미리 만들어 둡니다.
        revertImpactContext = entry.nodeKind == .directory
            ? RevertImpactContext(
                requestID: request.id,
                impact: TreeConflictRestoreScan.impact(
                    target: entry.path,
                    statuses: statuses,
                    containedFilePaths: { path in
                        conflictFileService.containedFilePaths(
                            relativePath: path,
                            workingCopyPath: project.path
                        )
                    }
                )
            )
            : nil
        revertRequest = request
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
                        .ui.file.noLongerMarkedDeleted
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
        if !restoredPaths.isEmpty {
            await loadWorkingCopyFiles()
        }
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
                .ui.file.restoredSelectedDeletionFileServer,
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
        let impact = revertImpact(for: request)
        revertRequest = nil
        revertImpactContext = nil
        let requestID = beginRequest(.revert)
        defer { finishRequest(requestID, kind: .revert) }
        let operationID = beginOperation(.revert(project.id))
        defer { endOperation(operationID) }
        do {
            // 복사로 추가한 폴더를 되돌리면 `svn revert`가 그 폴더를 디스크에서 지웁니다.
            // 버전관리되지 않은 파일은 저장소 이력에도 없으므로 먼저 복구본을 만듭니다.
            if let impact, !impact.isEmpty {
                _ = try conflictFileService.preserveSubtree(
                    relativePath: request.entry.path,
                    projectID: project.id,
                    workingCopyPath: project.path
                )
            }
            _ = try await client.revert(at: project.path, relativePath: request.entry.path, credentials: nil)
            guard canApplyRequest(
                requestID,
                kind: .revert,
                projectID: request.projectID
            ) else { return }
            selectedPaths.remove(request.entry.path)
            notice = AppLanguage.current.localized(.ui.file.revertedLocalChanges, request.entry.path)
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
        notice = AppLanguage.current.localized(.ui.file.copiedFilePath)
    }
}
