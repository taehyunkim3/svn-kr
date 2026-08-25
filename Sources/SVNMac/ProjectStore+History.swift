import Foundation
import SVNCore

struct HistoryRevisionRestoreRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let relativePath: String
    let revision: String
}

struct HistoryRevisionOperation: Identifiable, Equatable {
    enum Kind: Equatable {
        case save
        case restore
    }

    let id = UUID()
    let projectID: SVNProject.ID
    let relativePath: String
    let revision: String
    let kind: Kind
}

extension ProjectStore {
    func selectHistoryRevision(_ revision: String) {
        selectedHistoryRevision = revision
        selectedHistoryPath = nil
        historyDiffContent = .placeholder
    }

    func loadHistoryDiff(for revision: String, changedPath: SVNChangedPath) async {
        guard let project = selectedProject else { return }
        selectedHistoryRevision = revision
        selectedHistoryPath = changedPath.path
        historyDiffContent = .placeholder
        let operationID = beginOperation(.revisionDiff(project.id))
        defer { endOperation(operationID) }
        do {
            let value = try await client.revisionDiff(
                at: project.path,
                revision: revision,
                repositoryPath: changedPath.path,
                workingCopyRepositoryPath: workingCopyRepositoryPath,
                pegRevision: pegRevision(for: changedPath, revision: revision),
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id,
                  selectedHistoryRevision == revision,
                  selectedHistoryPath == changedPath.path else { return }
            historyDiffContent = value.isEmpty ? .noTextDiff : .text(value)
        } catch {
            if selectedProjectID == project.id,
               selectedHistoryRevision == revision,
               selectedHistoryPath == changedPath.path {
                historyDiffContent = .failure(localizedError(error))
            }
        }
    }

    private func pegRevision(for changedPath: SVNChangedPath, revision: String) -> String {
        guard changedPath.action == .deleted,
              let revisionNumber = Int(revision), revisionNumber > 0 else { return revision }
        return String(revisionNumber - 1)
    }

    func loadMoreHistory() async {
        guard let project = selectedProject,
              hasMoreHistory,
              let lastRevision = logs.last?.revision,
              let revision = Int(lastRevision), revision > 1 else { return }
        let operationID = beginOperation(.loadMoreHistory(project.id))
        defer { endOperation(operationID) }
        do {
            let olderLogs = try await client.log(
                at: project.path,
                limit: 50,
                endingAtRevision: String(revision - 1),
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard selectedProjectID == project.id else { return }
            let existingRevisions = Set(logs.map(\.revision))
            logs.append(contentsOf: olderLogs.filter { !existingRevisions.contains($0.revision) })
            hasMoreHistory = olderLogs.count == 50
        } catch {
            if selectedProjectID == project.id { errorMessage = localizedError(error) }
        }
    }

    var isHistoryRevisionOperationRunning: Bool {
        recoveryState.historyRevisionOperation?.projectID == selectedProjectID
    }

    func isSavingHistoryRevision(_ revision: String) -> Bool {
        guard let operation = recoveryState.historyRevisionOperation else { return false }
        return operation.projectID == selectedProjectID
            && operation.revision == revision
            && operation.kind == .save
    }

    func isRestoringHistoryRevision(_ revision: String) -> Bool {
        guard let operation = recoveryState.historyRevisionOperation else { return false }
        return operation.projectID == selectedProjectID
            && operation.revision == revision
            && operation.kind == .restore
    }

    func requestHistoryRevisionRestore(revision: String, relativePath: String) {
        guard let project = selectedProject,
              recoveryState.historyRevisionOperation == nil else { return }
        recoveryState.historyRevisionRestoreRequest = HistoryRevisionRestoreRequest(
            projectID: project.id,
            relativePath: relativePath,
            revision: revision
        )
    }

    func saveHistoryRevision(
        revision: String,
        relativePath: String,
        to destinationURL: URL
    ) async -> Bool {
        guard let project = selectedProject,
              recoveryState.historyRevisionOperation == nil else { return false }
        let operation = HistoryRevisionOperation(
            projectID: project.id,
            relativePath: relativePath,
            revision: revision,
            kind: .save
        )
        recoveryState.historyRevisionOperation = operation
        let operationID = beginOperation(.fileHistory(project.id))
        let accessesSecurityScope = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if accessesSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
            endOperation(operationID)
            if recoveryState.historyRevisionOperation?.id == operation.id {
                recoveryState.historyRevisionOperation = nil
            }
        }

        do {
            try await RevisionFileService().saveRevision(
                using: client,
                workingCopyPath: project.path,
                relativePath: relativePath,
                revision: revision,
                destinationURL: destinationURL,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard canApplyHistoryRevisionOperation(operation) else { return false }
            notice = AppLanguage.current.localized(
                .ui.saved.historicalRevision,
                revision,
                destinationURL.path
            )
            return true
        } catch {
            guard canApplyHistoryRevisionOperation(operation) else { return false }
            errorMessage = localizedError(error)
            return false
        }
    }

    func confirmHistoryRevisionRestore(_ request: HistoryRevisionRestoreRequest) async -> Bool {
        guard recoveryState.historyRevisionRestoreRequest == request,
              let project = selectedProject,
              project.id == request.projectID,
              recoveryState.historyRevisionOperation == nil else { return false }
        recoveryState.historyRevisionRestoreRequest = nil
        let operation = HistoryRevisionOperation(
            projectID: project.id,
            relativePath: request.relativePath,
            revision: request.revision,
            kind: .restore
        )
        recoveryState.historyRevisionOperation = operation
        let operationID = beginOperation(.revert(project.id))
        defer {
            endOperation(operationID)
            if recoveryState.historyRevisionOperation?.id == operation.id {
                recoveryState.historyRevisionOperation = nil
            }
        }

        do {
            let contents = try await client.fileContents(
                at: project.path,
                relativePath: request.relativePath,
                revision: request.revision,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: project)
            )
            guard canApplyHistoryRevisionOperation(operation) else { return false }
            _ = try await RevisionFileService().restoreWorkingFile(
                contents: contents,
                workingCopyPath: project.path,
                relativePath: request.relativePath,
                projectID: project.id,
                revision: request.revision
            )
            guard canApplyHistoryRevisionOperation(operation) else { return false }
            await refreshLocalWorkingCopy()
            guard canApplyHistoryRevisionOperation(operation) else { return false }
            notice = AppLanguage.current.localized(
                .ui.restored.revisionCommitRequired,
                request.relativePath,
                request.revision
            )
            return true
        } catch {
            guard canApplyHistoryRevisionOperation(operation) else { return false }
            errorMessage = localizedError(error)
            return false
        }
    }

    private func canApplyHistoryRevisionOperation(_ operation: HistoryRevisionOperation) -> Bool {
        selectedProjectID == operation.projectID
            && recoveryState.historyRevisionOperation?.id == operation.id
    }
}
