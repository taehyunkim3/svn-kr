import Testing
@testable import SVNMac

@Test func splitBrowserFolderTreeExcludesFiles() {
    var state = WorkingCopySplitBrowserState()
    state.cache([
        makeSplitBrowserNode("Sources", isDirectory: true),
        makeSplitBrowserNode("README.md", isDirectory: false),
    ], for: "")

    #expect(state.folderChildren(of: "").map(\.name) == ["Sources"])
    #expect(state.visibleFolderRows(rootName: "Working Copy").map(\.name) == ["Working Copy", "Sources"])
}

@Test func splitBrowserFlattensOnlyExpandedFolderRows() {
    var state = WorkingCopySplitBrowserState()
    state.cache([makeSplitBrowserNode("Sources", isDirectory: true, hasChildren: true)], for: "")
    state.cache([makeSplitBrowserNode("App", parent: "Sources", isDirectory: true)], for: "Sources")

    #expect(state.visibleFolderRows(rootName: "Root").map(\.relativePath) == ["", "Sources"])

    state.expandedDirectoryPaths.insert("Sources")
    #expect(state.visibleFolderRows(rootName: "Root").map(\.relativePath) == ["", "Sources", "Sources/App"])

    state.expandedDirectoryPaths.remove("")
    #expect(state.visibleFolderRows(rootName: "Root").map(\.relativePath) == [""])
}

@Test func splitBrowserLoadedFileOnlyFolderIsNotExpandableInFolderTree() {
    var state = WorkingCopySplitBrowserState()
    state.cache([makeSplitBrowserNode("Documents", isDirectory: true, hasChildren: true)], for: "")
    state.cache([
        makeSplitBrowserNode("proposal.pdf", parent: "Documents", isDirectory: false),
    ], for: "Documents")
    state.selectFolder("Documents")

    let documents = state.visibleFolderRows(rootName: "Root")
        .first { $0.relativePath == "Documents" }
    #expect(documents?.hasChildren == false)
    #expect(state.moveFolderRight() == nil)
    #expect(!state.expandedDirectoryPaths.contains("Documents"))
}

@Test func splitBrowserRightExpandsThenMovesToFirstChild() {
    var state = WorkingCopySplitBrowserState()
    state.cache([makeSplitBrowserNode("Sources", isDirectory: true, hasChildren: true)], for: "")
    state.cache([makeSplitBrowserNode("App", parent: "Sources", isDirectory: true)], for: "Sources")
    state.selectFolder("Sources")

    #expect(state.moveFolderRight() == nil)
    #expect(state.expandedDirectoryPaths.contains("Sources"))
    #expect(state.selectedFolderPath == "Sources")

    #expect(state.moveFolderRight() == "Sources/App")
    #expect(state.selectedFolderPath == "Sources/App")
    #expect(state.currentDirectoryPath == "Sources/App")
}

@Test func splitBrowserLeftCollapsesThenMovesToParent() {
    var state = WorkingCopySplitBrowserState()
    state.cache([makeSplitBrowserNode("Sources", isDirectory: true, hasChildren: true)], for: "")
    state.selectFolder("Sources")
    state.expandedDirectoryPaths.insert("Sources")

    state.moveFolderLeft()
    #expect(!state.expandedDirectoryPaths.contains("Sources"))
    #expect(state.selectedFolderPath == "Sources")

    state.moveFolderLeft()
    #expect(state.selectedFolderPath == "")
    #expect(state.currentDirectoryPath == "")
}

@Test func splitBrowserLeftAtRootIsSafe() {
    var state = WorkingCopySplitBrowserState()
    state.expandedDirectoryPaths.remove("")

    state.moveFolderLeft()

    #expect(state.selectedFolderPath == "")
    #expect(state.currentDirectoryPath == "")
}

@Test func splitBrowserEnteringContentFolderSynchronizesFolderSelection() {
    var state = WorkingCopySplitBrowserState()
    state.selectContent("Documents/Reports")

    state.enterDirectory("Documents/Reports")

    #expect(state.currentDirectoryPath == "Documents/Reports")
    #expect(state.selectedFolderPath == "Documents/Reports")
    #expect(state.selectedContentPath == nil)
    #expect(state.expandedDirectoryPaths.isSuperset(of: ["", "Documents"]))
}

@Test func splitBrowserContentLeftMovesToParentAndIsSafeAtRoot() {
    var state = WorkingCopySplitBrowserState()
    state.enterDirectory("Documents/Reports")

    state.moveToParentDirectory()
    #expect(state.currentDirectoryPath == "Documents")
    #expect(state.selectedFolderPath == "Documents")

    state.moveToParentDirectory()
    state.moveToParentDirectory()
    #expect(state.currentDirectoryPath == "")
    #expect(state.selectedFolderPath == "")
}

@Test func splitBrowserFocusChangesPreserveBothPanelSelections() {
    var state = WorkingCopySplitBrowserState()
    state.selectFolder("Sources")
    state.selectContent("Sources/App.swift")

    state.moveFocus()
    #expect(state.focusedPanel == .contents)
    #expect(state.selectedFolderPath == "Sources")
    #expect(state.selectedContentPath == "Sources/App.swift")

    state.moveFocus(reverse: true)
    #expect(state.focusedPanel == .folders)
    #expect(state.selectedFolderPath == "Sources")
    #expect(state.selectedContentPath == "Sources/App.swift")
}

@Test func splitBrowserArrowMovementUsesVisiblePanelRows() {
    var state = WorkingCopySplitBrowserState()
    let sources = makeSplitBrowserNode("Sources", isDirectory: true)
    let tests = makeSplitBrowserNode("Tests", isDirectory: true)
    let readme = makeSplitBrowserNode("README.md", isDirectory: false)
    state.cache([sources, tests, readme], for: "")

    state.moveFolderSelection(by: 1, rootName: "Root")
    #expect(state.selectedFolderPath == "Sources")
    state.moveFolderSelection(by: 1, rootName: "Root")
    #expect(state.selectedFolderPath == "Tests")

    state.moveContentSelection(by: 1, in: [sources, tests, readme])
    #expect(state.selectedContentPath == "Sources")
    state.moveContentSelection(by: -1, in: [sources, tests, readme])
    #expect(state.selectedContentPath == "Sources")

    state.selectFolder("")
    state.selectContent("README.md")
    state.moveFolderSelection(by: -1, rootName: "Root")
    #expect(state.selectedFolderPath == "")
    #expect(state.selectedContentPath == "README.md")
}

@Test func splitBrowserRefreshClearsEveryCachedDirectory() {
    var state = WorkingCopySplitBrowserState()
    state.cache([makeSplitBrowserNode("Sources", isDirectory: true)], for: "")
    state.cache([makeSplitBrowserNode("App.swift", parent: "Sources", isDirectory: false)], for: "Sources")

    state.clearCacheForRefresh()

    #expect(!state.isDirectoryCached(""))
    #expect(!state.isDirectoryCached("Sources"))
    #expect(state.directoryContentsByPath.isEmpty)
}

private func makeSplitBrowserNode(
    _ name: String,
    parent: String = "",
    isDirectory: Bool,
    hasChildren: Bool = false
) -> WorkingCopyFileNode {
    WorkingCopyFileNode(
        name: name,
        relativePath: parent.isEmpty ? name : "\(parent)/\(name)",
        isDirectory: isDirectory,
        isSymbolicLink: false,
        hasChildren: hasChildren,
        svnEntry: nil,
        children: nil
    )
}
