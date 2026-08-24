import Foundation
import Testing
@testable import SVNMac

@Test func visibleRowsFollowExpansionState() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())

    #expect(state.visibleRows().map(\.relativePath) == ["Folder", "root.txt"])

    state.expandedPaths.insert("Folder")
    #expect(state.visibleRows().map(\.relativePath) == [
        "Folder",
        "Folder/Nested",
        "Folder/child.txt",
        "root.txt",
    ])

    state.expandedPaths.insert("Folder/Nested")
    #expect(state.visibleRows().map(\.relativePath) == [
        "Folder",
        "Folder/Nested",
        "Folder/Nested/deep.txt",
        "Folder/child.txt",
        "root.txt",
    ])
}

@Test func rightArrowExpandsCollapsedFolderThenMovesToFirstChild() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())

    let expanded = state.handle(.right, selectedPath: "Folder")
    #expect(state.expandedPaths == ["Folder"])
    #expect(expanded.selectedPath == "Folder")

    let moved = state.handle(.right, selectedPath: "Folder")
    #expect(moved.selectedPath == "Folder/Nested")
}

@Test func rightArrowRequestsUncachedDirectoryContents() {
    let folder = browserNode("Folder", directory: true, hasChildren: true)
    var state = WorkingCopyBrowserTreeState()
    state.reset(rootNodes: [folder])

    let result = state.handle(.right, selectedPath: "Folder")

    #expect(state.expandedPaths == ["Folder"])
    #expect(result.directoryToLoad == "Folder")
}

@Test func leftArrowCollapsesExpandedFolderThenMovesToParent() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())
    state.expandedPaths = ["Folder", "Folder/Nested"]

    let collapsed = state.handle(.left, selectedPath: "Folder/Nested")
    #expect(collapsed.selectedPath == "Folder/Nested")
    #expect(!state.expandedPaths.contains("Folder/Nested"))

    let movedFromFolder = state.handle(.left, selectedPath: "Folder/Nested")
    #expect(movedFromFolder.selectedPath == "Folder")

    let movedFromFile = state.handle(.left, selectedPath: "Folder/child.txt")
    #expect(movedFromFile.selectedPath == "Folder")
}

@Test func leftArrowAtRootIsSafe() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())

    let result = state.handle(.left, selectedPath: "root.txt")

    #expect(result.selectedPath == "root.txt")
}

@Test func rightArrowOnFileDoesNothing() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())

    let result = state.handle(.right, selectedPath: "root.txt")

    #expect(result.selectedPath == "root.txt")
    #expect(result.directoryToLoad == nil)
    #expect(state.expandedPaths.isEmpty)
}

@Test func sizeFormattingIsEmptyForDirectoriesAndReadableForFiles() {
    let directory = browserNode("Folder", directory: true, fileSize: 1_536)
    let file = browserNode("archive.zip", fileSize: 1_536)

    #expect(WorkingCopyFileMetadataFormatting.sizeText(for: directory).isEmpty)
    let formatted = WorkingCopyFileMetadataFormatting.sizeText(for: file)
    #expect(!formatted.isEmpty)
    #expect(formatted != "1536")
}

@Test func resettingTreeClearsLoadedChildrenAndExpansion() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())
    state.expandedPaths = ["Folder"]
    state.setLoading(true, for: "Folder/Nested")
    let previousGeneration = state.generation

    state.reset(rootNodes: [browserNode("new.txt")])

    #expect(state.childrenByDirectory.isEmpty)
    #expect(state.expandedPaths.isEmpty)
    #expect(state.loadingPaths.isEmpty)
    #expect(state.generation != previousGeneration)
    #expect(state.rootNodes.map(\.relativePath) == ["new.txt"])
}

@Test func preparingTreeRefreshPreservesExpansionButClearsChildCache() {
    var state = WorkingCopyBrowserTreeState(recursiveTree: browserTestTree())
    state.expandedPaths = ["Folder", "Folder/Nested"]
    state.setLoading(true, for: "Folder/Nested")
    let previousGeneration = state.generation

    state.prepareForRefresh()

    #expect(state.expandedPaths == ["Folder", "Folder/Nested"])
    #expect(state.childrenByDirectory.isEmpty)
    #expect(state.loadingPaths.isEmpty)
    #expect(state.generation != previousGeneration)
}

@Test func treeRefreshPlanRestoresDirectoriesShallowestFirst() {
    var state = WorkingCopyBrowserTreeState()
    state.expandedPaths = ["Sources/App", "Tests", "Sources"]

    let plan = state.refreshPlan(selectedPath: "Sources/App/Feature/file.swift")

    #expect(plan.directoryPaths == ["Sources", "Tests", "Sources/App", "Sources/App/Feature"])
    #expect(plan.selectionAncestorPaths == ["Sources", "Sources/App", "Sources/App/Feature"])
}

@Test func finishingTreeRefreshRemovesMissingExpansionAndValidatesSelection() {
    var state = WorkingCopyBrowserTreeState()
    state.expandedPaths = ["Existing", "Existing/Nested", "Missing"]
    state.replaceRootNodesForRefresh([
        browserNode("Existing", directory: true, hasChildren: true),
    ])
    state.cache([
        browserNode("Existing/Nested", directory: true, hasChildren: true),
    ], for: "Existing")
    state.cache([
        browserNode("Existing/Nested/file.txt"),
    ], for: "Existing/Nested")

    let preservedSelection = state.finishRefresh(selectedPath: "Existing/Nested/file.txt")

    #expect(state.expandedPaths == ["Existing", "Existing/Nested"])
    #expect(preservedSelection == "Existing/Nested/file.txt")
    #expect(state.finishRefresh(selectedPath: "Missing/file.txt") == nil)
}

private func browserTestTree() -> [WorkingCopyFileNode] {
    [
        browserNode(
            "Folder",
            directory: true,
            children: [
                browserNode(
                    "Folder/Nested",
                    directory: true,
                    children: [browserNode("Folder/Nested/deep.txt")]
                ),
                browserNode("Folder/child.txt"),
            ]
        ),
        browserNode("root.txt"),
    ]
}

private func browserNode(
    _ path: String,
    directory: Bool = false,
    fileSize: Int? = nil,
    hasChildren: Bool? = nil,
    children: [WorkingCopyFileNode]? = nil
) -> WorkingCopyFileNode {
    WorkingCopyFileNode(
        name: path.split(separator: "/").last.map(String.init) ?? path,
        relativePath: path,
        isDirectory: directory,
        isSymbolicLink: false,
        fileSize: fileSize,
        hasChildren: hasChildren,
        svnEntry: nil,
        children: children
    )
}
