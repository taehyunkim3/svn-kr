import Foundation
import SVNCore

extension ProjectStore {
    func update() async {
        guard let project = selectedProject,
              !activeOperations.contains(where: { $0.kind == .update(project.id) }) else { return }
        let commitRecovery = recoveryState.outOfDateCommitRecoveryRequest.flatMap {
            $0.projectID == project.id ? $0 : nil
        }
        let cleanupCandidatePaths = repositoryTemporaryFileCleanupCandidates.map(\.path)
        let preparesCleanup = cleansRepositoryTemporaryFilesAfterUpdate && !cleanupCandidatePaths.isEmpty
        let operationID = beginOperation(.update(project.id))
        defer { endOperation(operationID) }
        do {
            let result = try await client.update(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedProjectID == project.id else { return }
            notice = result
            cleansRepositoryTemporaryFilesAfterUpdate = false
            if preparesCleanup {
                temporaryFileCleanupAssessments = TemporaryFilePolicy.validateRepositoryCleanupCandidates(
                    paths: cleanupCandidatePaths,
                    in: URL(fileURLWithPath: project.path, isDirectory: true)
                )
                selectedTemporaryFileCleanupPaths = Set(
                    temporaryFileCleanupAssessments.lazy.filter(\.isEligible).map(\.path)
                )
                temporaryFileCleanupFailures = []
            }
            await refresh()
            guard selectedProjectID == project.id else { return }
            if let commitRecovery {
                await retryCommitAfterUpdate(commitRecovery)
                return
            }
            isShowingUpdatePreview = false
            if preparesCleanup, selectedProjectID == project.id {
                await Task.yield()
                isShowingTemporaryFileCleanup = true
            }
        } catch {
            if selectedProjectID == project.id {
                let action = commitRecovery.map {
                    SVNAuthenticationAction.commit(message: $0.message)
                } ?? .update
                handleRemoteError(error, project: project, action: action)
            }
        }
    }

    func prepareOutOfDateCommitRecovery(
        project: SVNProject,
        message: String,
        paths: [String],
        details: String
    ) async {
        recoveryState.outOfDateCommitRecoveryRequest = OutOfDateCommitRecoveryRequest(
            projectID: project.id,
            message: message,
            paths: paths,
            details: details
        )
        errorMessage = nil
        await previewUpdate()
    }

    private func retryCommitAfterUpdate(_ recovery: OutOfDateCommitRecoveryRequest) async {
        recoveryState.outOfDateCommitRecoveryRequest?.hasCompletedUpdate = true
        let conflicts = statuses.lazy
            .filter { $0.item == .conflicted || $0.propertyState == .conflicted }
            .map(\.path)
            .sorted()
        if !conflicts.isEmpty {
            recoveryState.outOfDateCommitRecoveryRequest?.conflictedPaths = conflicts
            notice = AppLanguage.current.localized(
                .ui.update.createdConflictsSoCommitNotRetried,
                conflicts.joined(separator: ", ")
            )
            return
        }

        let retryPaths = Set(recovery.paths)
        guard retryPaths.isSubset(of: selectableStatusPaths) else {
            isShowingUpdatePreview = false
            errorMessage = AppLanguage.current.localized(
                .ui.update.someSavedCommitSelectionsDisappearedChangeListAfterUpdateReview
            )
            return
        }
        selectedPaths = retryPaths
        // 삭제(missing) 항목은 커밋 전에 저장소 삭제 예약이 필요합니다.
        // commit(message:)는 그 항목을 거부하므로 예약을 포함한 경로로 재시도합니다.
        _ = await commitSelectedChanges(message: recovery.message)
    }

    func previewUpdate() async {
        guard let project = selectedProject else { return }
        let requestID = beginRequest(.updatePreview)
        let operationID = beginOperation(.previewUpdate(project.id))
        defer {
            finishRequest(requestID, kind: .updatePreview)
            endOperation(operationID)
        }
        recoveryState.updatePreview.beginLoading()
        remoteChanges = []
        cleansRepositoryTemporaryFilesAfterUpdate = false
        temporaryFileCleanupAssessments = []
        selectedTemporaryFileCleanupPaths = []
        temporaryFileCleanupFailures = []

        do {
            let commits: [SVNLogEntry]
            if isDemoMode {
                commits = logs
            } else {
                commits = try await client.updatePreviewIncomingCommits(
                    at: project.path,
                    credentials: credentials(for: project),
                    allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                    allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
                )
            }
            guard canApplyRequest(requestID, kind: .updatePreview, projectID: project.id) else { return }
            recoveryState.updatePreview.receive(commits)
        } catch {
            guard canApplyRequest(requestID, kind: .updatePreview, projectID: project.id) else { return }
            recordUpdatePreviewFailure(error, project: project)
        }

        do {
            let changes = try await client.remoteChanges(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard canApplyRequest(requestID, kind: .updatePreview, projectID: project.id) else { return }
            remoteChanges = changes
        } catch {
            guard canApplyRequest(requestID, kind: .updatePreview, projectID: project.id) else { return }
            recordUpdatePreviewFailure(error, project: project)
        }

        guard canApplyRequest(requestID, kind: .updatePreview, projectID: project.id) else { return }
        updateRemoteSummary(
            for: project.id,
            needsUpdate: recoveryState.outOfDateCommitRecoveryRequest != nil
                || recoveryState.updatePreview.totalCommitCount > 0
                || !remoteChanges.isEmpty
        )
        isShowingUpdatePreview = workingCopyCleanupRequest == nil && authenticationRequest == nil
    }

    private func recordUpdatePreviewFailure(_ error: Error, project: SVNProject) {
        recoveryState.updatePreview.recordFailure(localizedError(error))
        handleRemoteError(error, project: project, action: .update)
        if workingCopyCleanupRequest == nil, authenticationRequest == nil {
            errorMessage = nil
        }
    }

    func confirmRepositoryTemporaryFileCleanup() async {
        guard let project = selectedProject,
              !activeOperations.contains(where: {
                  $0.kind == .cleanupTemporaryFiles(project.id)
              }) else { return }
        let eligiblePaths = Set(temporaryFileCleanupAssessments.lazy.filter(\.isEligible).map(\.path))
        let requestedPaths = selectedTemporaryFileCleanupPaths.intersection(eligiblePaths).sorted()
        guard !requestedPaths.isEmpty else { return }

        let operationID = beginOperation(.cleanupTemporaryFiles(project.id))
        defer { endOperation(operationID) }

        var failures: [TemporaryFileCleanupFailure] = []
        var scheduledPaths: [String] = []
        do {
            let projectCredentials = try credentials(for: project)
            for path in requestedPaths {
                do {
                    if let lock = try await client.lockInfo(
                        at: project.path,
                        relativePath: path,
                        credentials: projectCredentials,
                        allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                        allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
                    ), lock.owner != project.username {
                        failures.append(TemporaryFileCleanupFailure(
                            path: path,
                            reason: AppLanguage.current.localized(
                                .ui.update.lockedRepository,
                                lock.owner
                            )
                        ))
                        continue
                    }
                    try await client.scheduleRepositoryCleanupDeletion(
                        at: project.path,
                        relativePath: path,
                        credentials: projectCredentials
                    )
                    scheduledPaths.append(path)
                } catch {
                    failures.append(TemporaryFileCleanupFailure(
                        path: path,
                        reason: localizedError(error)
                    ))
                }
            }

            guard selectedProjectID == project.id else { return }
            temporaryFileCleanupFailures = failures
            selectedTemporaryFileCleanupPaths = Set(scheduledPaths)
            guard !scheduledPaths.isEmpty else {
                errorMessage = cleanupFailureMessage(failures)
                return
            }

            do {
                let result = try await client.commit(
                    at: project.path,
                    paths: scheduledPaths,
                    message: repositoryTemporaryFileCleanupCommitMessage(paths: scheduledPaths),
                    credentials: projectCredentials,
                    allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                    allowedServerCertificateFailures: allowedServerCertificateFailures(for: project),
                    progress: nil
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard selectedProjectID == project.id else { return }
                isShowingTemporaryFileCleanup = false
                notice = AppLanguage.current.localized(
                    .ui.update.cleanedRepositoryTemporaryFile,
                    scheduledPaths.count,
                    result
                )
                if !failures.isEmpty {
                    errorMessage = cleanupFailureMessage(failures)
                }
                await refresh()
            } catch {
                for path in scheduledPaths {
                    _ = try? await client.revert(
                        at: project.path,
                        relativePath: path,
                        credentials: projectCredentials
                    )
                }
                guard selectedProjectID == project.id else { return }
                let reason = localizedError(error)
                failures += scheduledPaths.map {
                    TemporaryFileCleanupFailure(path: $0, reason: reason)
                }
                temporaryFileCleanupFailures = failures
                errorMessage = AppLanguage.current.localized(
                    .ui.update.succeededButCleanupCommitFailedScheduledDeletionsRestored,
                    reason
                )
            }
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = AppLanguage.current.localized(
                .ui.update.succeededButCleanupCouldNotStart,
                localizedError(error)
            )
        }
    }

    private func repositoryTemporaryFileCleanupCommitMessage(paths: [String]) -> String {
        "Mac/Office 임시파일 정리\n\n" + paths.map { "- \($0)" }.joined(separator: "\n")
    }

    private func cleanupFailureMessage(_ failures: [TemporaryFileCleanupFailure]) -> String? {
        guard !failures.isEmpty else { return nil }
        let details = failures.map { "\($0.path): \($0.reason)" }.joined(separator: "\n")
        return AppLanguage.current.localized(.ui.update.someTemporaryFilesNotCleaned, details)
    }
}
