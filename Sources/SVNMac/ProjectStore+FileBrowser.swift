import Foundation

extension ProjectStore {
    func refreshForMainWindowActivation() async {
        guard !isDemoMode,
              let project = selectedProject,
              !isWorking,
              automaticRefreshCanRun(for: project),
              ensureWorkingCopyDirectoryExists(for: project) else { return }

        let cycleID = UUID()
        let errorPolicy = RefreshErrorPolicy.coordinated(cycleID)
        async let changes: Void = refreshLocalWorkingCopy(errorPolicy: errorPolicy)
        async let files: Void = loadWorkingCopyFiles(errorPolicy: errorPolicy)
        _ = await (changes, files)
        finishRefreshCycle(cycleID)
    }

    func refreshWorkingCopyBrowser(
        errorPolicy: RefreshErrorPolicy = .standalone
    ) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project),
              let projectID = selectedProjectID,
              !activeOperations.contains(where: { $0.kind == .browseFiles(projectID) }) else { return }
        async let files: Void = loadWorkingCopyFiles(errorPolicy: errorPolicy)
        async let locks: Void = loadRepositoryLocks(errorPolicy: errorPolicy)
        _ = await (files, locks)
    }

    func loadWorkingCopyFiles(
        errorPolicy: RefreshErrorPolicy = .standalone
    ) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return }
        let requestID = beginRequest(.fileTree)
        let operationID = beginOperation(.browseFiles(project.id))
        defer { endOperation(operationID) }

        do {
            let svnEntries = try await client.workingCopyEntries(at: project.path, credentials: nil)
            let tree = try await workingCopyFileService.tree(at: project.path, svnEntries: svnEntries)
            guard canApplyRequest(requestID, kind: .fileTree, projectID: project.id) else { return }
            workingCopyFileTree = tree
            if let selectedBrowserPath,
               !tree.contains(relativePath: selectedBrowserPath) {
                self.selectedBrowserPath = nil
            }
        } catch {
            guard canApplyRequest(requestID, kind: .fileTree, projectID: project.id) else { return }
            publishRefreshError(error, projectID: project.id, policy: errorPolicy)
        }
    }
}

private extension Array where Element == WorkingCopyFileNode {
    func contains(relativePath: String) -> Bool {
        contains { node in
            node.relativePath == relativePath || node.children?.contains(relativePath: relativePath) == true
        }
    }
}
