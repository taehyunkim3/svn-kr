import SVNCore

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
                pegRevision: pegRevision(for: changedPath, revision: revision),
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
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
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            let existingRevisions = Set(logs.map(\.revision))
            logs.append(contentsOf: olderLogs.filter { !existingRevisions.contains($0.revision) })
            hasMoreHistory = olderLogs.count == 50
        } catch {
            if selectedProjectID == project.id { errorMessage = localizedError(error) }
        }
    }
}
