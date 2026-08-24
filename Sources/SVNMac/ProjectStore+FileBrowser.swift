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
        workingCopyBrowserRefreshGeneration &+= 1
        let requestID = beginRequest(.fileTree)
        let operationID = beginOperation(.browseFiles(project.id))
        defer { endOperation(operationID) }

        var clearedState = workingCopyBrowserTreeState
        clearedState.reset()
        workingCopyBrowserTreeState = clearedState
        workingCopyBrowserSVNEntries = []

        do {
            let svnEntries = try await client.workingCopyEntries(at: project.path, credentials: nil)
            let rootNodes = try await workingCopyFileService.directoryContents(
                at: project.path,
                relativeDirectory: "",
                svnEntries: svnEntries
            )
            guard canApplyRequest(requestID, kind: .fileTree, projectID: project.id) else { return }
            var state = workingCopyBrowserTreeState
            state.reset(rootNodes: rootNodes)
            workingCopyBrowserTreeState = state
            workingCopyBrowserSVNEntries = svnEntries
            if let selectedBrowserPath,
               state.node(at: selectedBrowserPath) == nil {
                self.selectedBrowserPath = nil
            }
        } catch {
            guard canApplyRequest(requestID, kind: .fileTree, projectID: project.id) else { return }
            publishRefreshError(error, projectID: project.id, policy: errorPolicy)
        }
    }

    func loadWorkingCopyDirectoryContents(
        at relativeDirectory: String,
        errorPolicy: RefreshErrorPolicy = .standalone
    ) async -> [WorkingCopyFileNode]? {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return nil }
        let operationID = beginOperation(.browseFiles(project.id))
        defer { endOperation(operationID) }

        do {
            let svnEntries = try await client.workingCopyEntries(at: project.path, credentials: nil)
            let contents = try await workingCopyFileService.directoryContents(
                at: project.path,
                relativeDirectory: relativeDirectory,
                svnEntries: svnEntries
            )
            guard selectedProjectID == project.id else { return nil }
            return contents
        } catch {
            publishRefreshError(error, projectID: project.id, policy: errorPolicy)
            return nil
        }
    }

    func setWorkingCopyDirectory(_ relativePath: String, expanded: Bool) -> String? {
        var state = workingCopyBrowserTreeState
        let directoryToLoad = state.setExpanded(expanded, for: relativePath)
        workingCopyBrowserTreeState = state
        return directoryToLoad
    }

    func applyWorkingCopyBrowserKey(
        _ command: WorkingCopyBrowserKeyCommand,
        sortedBy comparator: WorkingCopyFileSortComparator
    ) -> WorkingCopyBrowserNavigationResult {
        var state = workingCopyBrowserTreeState
        let result = state.handle(
            command,
            selectedPath: selectedBrowserPath,
            sortedBy: comparator
        )
        workingCopyBrowserTreeState = state
        selectedBrowserPath = result.selectedPath
        return result
    }

    func loadWorkingCopyDirectory(_ relativePath: String) async {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return }
        var state = workingCopyBrowserTreeState
        guard let node = state.node(at: relativePath),
              node.isDirectory,
              node.hasChildren,
              !state.hasCachedChildren(for: relativePath),
              !state.loadingPaths.contains(relativePath) else { return }

        let generation = state.generation
        let svnEntries = workingCopyBrowserSVNEntries
        state.setLoading(true, for: relativePath)
        workingCopyBrowserTreeState = state

        do {
            let children = try await workingCopyFileService.directoryContents(
                at: project.path,
                relativeDirectory: relativePath,
                svnEntries: svnEntries
            )
            guard selectedProjectID == project.id,
                  workingCopyBrowserTreeState.generation == generation else { return }
            var currentState = workingCopyBrowserTreeState
            currentState.cache(children, for: relativePath)
            workingCopyBrowserTreeState = currentState
        } catch {
            guard selectedProjectID == project.id,
                  workingCopyBrowserTreeState.generation == generation else { return }
            var currentState = workingCopyBrowserTreeState
            currentState.setLoading(false, for: relativePath)
            workingCopyBrowserTreeState = currentState
            publishRefreshError(error, projectID: project.id, policy: .standalone)
        }
    }

    func searchWorkingCopyFiles(query: String) async -> [WorkingCopyFileNode]? {
        guard let project = selectedProject,
              ensureWorkingCopyDirectoryExists(for: project) else { return nil }
        let generation = workingCopyBrowserTreeState.generation
        let svnEntries = workingCopyBrowserSVNEntries

        do {
            let tree = try await workingCopyFileService.tree(
                at: project.path,
                svnEntries: svnEntries
            )
            guard !Task.isCancelled,
                  selectedProjectID == project.id,
                  workingCopyBrowserTreeState.generation == generation else { return nil }
            let input = WorkingCopyFileTreeFilterInput(tree: tree, query: query)
            return await Task.detached { input.filteredTree }.value
        } catch is CancellationError {
            return nil
        } catch {
            guard selectedProjectID == project.id,
                  workingCopyBrowserTreeState.generation == generation else { return nil }
            publishRefreshError(error, projectID: project.id, policy: .standalone)
            return []
        }
    }
}
