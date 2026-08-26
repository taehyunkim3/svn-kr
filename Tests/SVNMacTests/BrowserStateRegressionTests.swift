import Foundation
import SVNCore
import Testing
@testable import SVNMac

@MainActor
@Test func repositoryBrowserFileSelectionKeepsTheCurrentCheckoutURL() async {
    let repositoryURL = "https://svn.example.com/office/trunk"
    let state = RepositoryBrowserState(
        repositoryEntries: { _, _, _, _, _ in
            [repositoryEntry("보고서.xlsx", kind: .file)]
        },
        repositoryURL: repositoryURL
    )

    await state.browse()
    state.selectedEntryID = "보고서.xlsx"

    #expect(state.checkoutURL == repositoryURL)
}

@MainActor
@Test func repositoryBrowserReplacementActionRunsAfterCancelingThePreviousLoad() async {
    let firstURL = "https://svn.example.com/office/first"
    let secondURL = "https://svn.example.com/office/second"
    let probe = RepositoryBrowserReplacementProbe(firstURL: firstURL)
    let state = RepositoryBrowserState(
        repositoryEntries: probe.load,
        repositoryURL: firstURL
    )

    let first = state.beginBrowse()
    await probe.waitUntilFirstRequestStarts()
    state.repositoryURLInput = secondURL
    let second = state.beginBrowse()
    await second.value
    await first.value

    #expect(await probe.requestedURLs() == [firstURL, secondURL])
    #expect(state.currentURL == secondURL)
    #expect(state.phase == .loaded)
}

@Test func browserRefreshRechecksNeedsLockAndSearchAlwaysSettles() throws {
    let splitBrowser = try source("WorkingCopySplitBrowserView.swift")
    let refreshStart = try #require(splitBrowser.range(of: "private func reloadCachedDirectories() async"))
    let refreshTail = splitBrowser[refreshStart.lowerBound...]
    let refreshEnd = try #require(refreshTail.range(of: "\n    private func loadDirectory"))
    let refresh = refreshTail[..<refreshEnd.lowerBound]
    #expect(refresh.contains("await store.loadNeedsLockState("))

    let treeBrowser = try source("WorkingCopyBrowserView.swift")
    let searchStart = try #require(treeBrowser.range(of: "private func updateSearchResults() async"))
    let searchTail = treeBrowser[searchStart.lowerBound...]
    let searchEnd = try #require(searchTail.range(of: "\n    private func setDirectory"))
    let search = searchTail[..<searchEnd.lowerBound]
    #expect(search.contains("let request = searchRequest"))
    #expect(occurrences(of: "isSearching = false", in: String(search)) >= 3)
}

private actor RepositoryBrowserReplacementProbe {
    private let firstURL: String
    private var requests: [String] = []
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []

    init(firstURL: String) {
        self.firstURL = firstURL
    }

    func load(
        repositoryURL: String,
        revision: String?,
        credentials: SVNCredentials?,
        allowsUntrusted: Bool,
        failures: Set<SVNServerCertificateFailure>
    ) async throws -> [SVNRepositoryEntry] {
        _ = (revision, credentials, allowsUntrusted, failures)
        requests.append(repositoryURL)
        if repositoryURL == firstURL {
            let waiters = firstRequestWaiters
            firstRequestWaiters.removeAll()
            waiters.forEach { $0.resume() }
            try await Task.sleep(for: .seconds(60))
        }
        return []
    }

    func waitUntilFirstRequestStarts() async {
        guard requests.contains(firstURL) else {
            await withCheckedContinuation { continuation in
                firstRequestWaiters.append(continuation)
            }
            return
        }
    }

    func requestedURLs() -> [String] {
        requests
    }
}

private func repositoryEntry(
    _ name: String,
    kind: SVNRepositoryEntryKind
) -> SVNRepositoryEntry {
    SVNRepositoryEntry(
        name: name,
        kind: kind,
        size: kind == .file ? 100 : nil,
        lastChangedRevision: "42",
        lastChangedAuthor: "office.user",
        lastChangedDate: nil
    )
}

private func source(_ fileName: String) throws -> String {
    try String(
        contentsOf: svnMacSources().appendingPathComponent(fileName),
        encoding: .utf8
    )
}

private func occurrences(of needle: String, in value: String) -> Int {
    value.components(separatedBy: needle).count - 1
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
