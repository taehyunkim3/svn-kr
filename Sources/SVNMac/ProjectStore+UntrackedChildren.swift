import Foundation
import SVNCore

extension ProjectStore {
    func setUntrackedDirectoryExpanded(_ directory: String, expanded: Bool) async {
        guard expanded else {
            expandedUntrackedDirectoryPaths.remove(directory)
            return
        }

        expandedUntrackedDirectoryPaths.insert(directory)
        guard untrackedChildrenByDirectory[directory] == nil,
              !loadingUntrackedDirectoryPaths.contains(directory),
              let project = selectedProject else { return }
        let refreshGeneration = untrackedChildrenRefreshGeneration
        loadingUntrackedDirectoryPaths.insert(directory)
        untrackedChildrenErrorsByDirectory[directory] = nil

        do {
            let children = try await client.untrackedChildren(
                at: project.path,
                directory: directory,
                credentials: credentials(for: project)
            )
            guard selectedProjectID == project.id,
                  untrackedChildrenRefreshGeneration == refreshGeneration else { return }
            loadingUntrackedDirectoryPaths.remove(directory)
            untrackedChildrenByDirectory[directory] = children
        } catch {
            guard selectedProjectID == project.id,
                  untrackedChildrenRefreshGeneration == refreshGeneration else { return }
            loadingUntrackedDirectoryPaths.remove(directory)
            untrackedChildrenErrorsByDirectory[directory] = localizedError(error)
        }
    }

    func visibleUntrackedChildren(in directory: String) -> [SVNUntrackedChild] {
        (untrackedChildrenByDirectory[directory] ?? []).filter {
            showsIgnoredFiles || !$0.isIgnored
        }
    }

    func visibleUntrackedDescendants(in directory: String) -> [VisibleUntrackedChild] {
        var result: [VisibleUntrackedChild] = []
        var pending = visibleUntrackedChildren(in: directory).reversed().map {
            VisibleUntrackedChild(child: $0, parentDirectory: directory, depth: 1)
        }
        while let row = pending.popLast() {
            result.append(row)
            guard row.child.isDirectory,
                  expandedUntrackedDirectoryPaths.contains(row.child.path) else { continue }
            pending.append(contentsOf: visibleUntrackedChildren(in: row.child.path).reversed().map {
                VisibleUntrackedChild(
                    child: $0,
                    parentDirectory: row.child.path,
                    depth: row.depth + 1
                )
            })
        }
        return result
    }

    func setUntrackedDirectorySelected(_ directory: String, selected: Bool) {
        guard selected else {
            selectedPaths.remove(directory)
            selectedUntrackedChildPaths.remove(directory)
            return
        }
        removeSelectedUntrackedAncestors(of: directory)
        removeSelectedUntrackedDescendants(of: directory)
        if selectableStatusPaths.contains(directory) {
            selectedPaths.insert(directory)
        } else if knownUntrackedChildPaths.contains(directory) {
            selectedUntrackedChildPaths.insert(directory)
        }
    }

    func setUntrackedChildSelected(
        _ path: String,
        parentDirectory: String,
        selected: Bool
    ) {
        guard selected else {
            selectedUntrackedChildPaths.remove(path)
            return
        }
        guard untrackedChildrenByDirectory[parentDirectory]?.contains(where: {
            $0.path == path
        }) == true else { return }
        removeSelectedUntrackedAncestors(of: path)
        removeSelectedUntrackedDescendants(of: path)
        selectedUntrackedChildPaths.insert(path)
    }

    func isUntrackedChildSelectionDisabled(in parentDirectory: String) -> Bool {
        selectedCommitPaths().contains { selectedPath in
            Self.path(parentDirectory, isAtOrBelow: selectedPath)
        }
    }

    func selectedCommitPaths() -> Set<String> {
        selectedPaths.union(selectedUntrackedChildPaths)
    }

    func selectAllCommitPaths() {
        selectedUntrackedChildPaths.removeAll()
        selectedPaths = selectAllStatusPaths
    }

    func clearCommitSelection() {
        selectedPaths.removeAll()
        selectedUntrackedChildPaths.removeAll()
    }

    func discardUntrackedChildrenState() {
        untrackedChildrenRefreshGeneration += 1
        expandedUntrackedDirectoryPaths.removeAll()
        untrackedChildrenByDirectory.removeAll()
        loadingUntrackedDirectoryPaths.removeAll()
        untrackedChildrenErrorsByDirectory.removeAll()
        selectedUntrackedChildPaths.removeAll()
    }

    func removeUntrackedChildSelectionsCovered(by paths: Set<String>) {
        selectedUntrackedChildPaths = Set(selectedUntrackedChildPaths.filter { childPath in
            !paths.contains { Self.path(childPath, isBelow: $0) }
        })
    }

    private var knownUntrackedChildPaths: Set<String> {
        Set(untrackedChildrenByDirectory.values.joined().map(\.path))
    }

    private func removeSelectedUntrackedAncestors(of path: String) {
        selectedPaths = Set(selectedPaths.filter { !Self.path(path, isBelow: $0) })
        selectedUntrackedChildPaths = Set(selectedUntrackedChildPaths.filter {
            !Self.path(path, isBelow: $0)
        })
    }

    private func removeSelectedUntrackedDescendants(of path: String) {
        selectedUntrackedChildPaths = Set(selectedUntrackedChildPaths.filter {
            !Self.path($0, isBelow: path)
        })
    }

    private static func path(_ candidate: String, isAtOrBelow root: String) -> Bool {
        candidate == root || path(candidate, isBelow: root)
    }

    private static func path(_ candidate: String, isBelow root: String) -> Bool {
        Data(candidate.utf8).starts(with: Data(root.utf8) + Data([0x2F]))
    }
}
