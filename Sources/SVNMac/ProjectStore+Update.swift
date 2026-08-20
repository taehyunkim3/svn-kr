import Foundation

extension ProjectStore {
    func update() async {
        guard let project = selectedProject else { return }
        let cleanupCandidatePaths = repositoryTemporaryFileCleanupCandidates.map(\.path)
        let preparesCleanup = cleansRepositoryTemporaryFilesAfterUpdate && !cleanupCandidatePaths.isEmpty
        let operationID = beginOperation(.update(project.id))
        defer { endOperation(operationID) }
        do {
            let result = try await client.update(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedProjectID == project.id else { return }
            notice = result
            isShowingUpdatePreview = false
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
            if preparesCleanup, selectedProjectID == project.id {
                await Task.yield()
                isShowingTemporaryFileCleanup = true
            }
        } catch {
            if selectedProjectID == project.id { handleRemoteError(error, project: project, action: .update) }
        }
    }

    func previewUpdate() async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.previewUpdate(project.id))
        defer { endOperation(operationID) }
        do {
            let changes = try await client.remoteChanges(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            remoteChanges = changes
            cleansRepositoryTemporaryFilesAfterUpdate = false
            temporaryFileCleanupAssessments = []
            selectedTemporaryFileCleanupPaths = []
            temporaryFileCleanupFailures = []
            updateRemoteSummary(for: project.id, needsUpdate: !changes.isEmpty)
            isShowingUpdatePreview = true
        } catch {
            guard selectedProjectID == project.id else { return }
            handleRemoteError(error, project: project, action: .update)
        }
    }

    func confirmRepositoryTemporaryFileCleanup() async {
        guard let project = selectedProject else { return }
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
                        allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
                    ), lock.owner != project.username {
                        failures.append(TemporaryFileCleanupFailure(
                            path: path,
                            reason: AppLanguage.current.localized(
                                "ui.cleanup.reason.locked.by.5ee975b0",
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
                    allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard selectedProjectID == project.id else { return }
                isShowingTemporaryFileCleanup = false
                notice = AppLanguage.current.localized(
                    "ui.cleaned.repository.temporary.files.75d9479a",
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
                    "ui.cleanup.commit.failed.update.succeeded.f59c27fb",
                    reason
                )
            }
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = AppLanguage.current.localized(
                "ui.cleanup.could.not.start.update.succeeded.bfae6b76",
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
        return AppLanguage.current.localized("ui.cleanup.some.items.failed.2bdf30af", details)
    }
}
