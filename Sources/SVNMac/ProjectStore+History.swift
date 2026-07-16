import SVNCore

extension ProjectStore {
    func loadHistoryDiff(for revision: String) async {
        guard let project = selectedProject else { return }
        selectedHistoryRevision = revision
        historyDiffContent = .placeholder
        let operationID = beginOperation(.revisionDiff(project.id))
        defer { endOperation(operationID) }
        do {
            let value = try await client.revisionDiff(
                at: project.path,
                revision: revision,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id, selectedHistoryRevision == revision else { return }
            historyDiffContent = value.isEmpty ? .noTextDiff : .text(value)
        } catch {
            if selectedProjectID == project.id { errorMessage = localizedError(error) }
        }
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
