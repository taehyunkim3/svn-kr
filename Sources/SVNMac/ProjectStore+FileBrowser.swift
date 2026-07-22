import Foundation

extension ProjectStore {
    func refreshForMainWindowActivation() async {
        guard !isDemoMode, selectedProject != nil, !isWorking else { return }
        async let changes: Void = refreshLocalWorkingCopy()
        async let files: Void = loadWorkingCopyFiles()
        _ = await (changes, files)
    }

    func refreshWorkingCopyBrowser() async {
        guard let projectID = selectedProjectID,
              !activeOperations.contains(where: { $0.kind == .browseFiles(projectID) }) else { return }
        async let files: Void = loadWorkingCopyFiles()
        async let locks: Void = loadRepositoryLocks()
        _ = await (files, locks)
    }

    func loadWorkingCopyFiles() async {
        guard let project = selectedProject else { return }
        let requestID = UUID()
        fileTreeRequestID = requestID
        let operationID = beginOperation(.browseFiles(project.id))
        defer { endOperation(operationID) }

        do {
            let svnEntries = try await client.workingCopyEntries(at: project.path, credentials: nil)
            let tree = try await workingCopyFileService.tree(at: project.path, svnEntries: svnEntries)
            guard fileTreeRequestID == requestID, selectedProjectID == project.id else { return }
            workingCopyFileTree = tree
            if let selectedBrowserPath,
               !tree.contains(relativePath: selectedBrowserPath) {
                self.selectedBrowserPath = nil
            }
        } catch {
            guard fileTreeRequestID == requestID, selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
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
