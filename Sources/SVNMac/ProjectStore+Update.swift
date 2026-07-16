import Foundation

extension ProjectStore {
    func update() async {
        guard let project = selectedProject else { return }
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
            await refresh()
        } catch {
            if selectedProjectID == project.id { handleRemoteError(error, project: project, action: .update) }
        }
    }

    func previewUpdate() async {
        guard let project = selectedProject else { return }
        let operationID = beginOperation(.previewUpdate(project.id))
        defer { endOperation(operationID) }
        do {
            remoteChanges = try await client.remoteChanges(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate: project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            updateRemoteSummary(for: project.id, needsUpdate: !remoteChanges.isEmpty)
            isShowingUpdatePreview = true
        } catch {
            handleRemoteError(error, project: project, action: .update)
        }
    }
}
