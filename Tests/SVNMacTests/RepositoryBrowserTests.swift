import Foundation
import SVNCore
import Testing
@testable import SVNMac

@MainActor
@Test func repositoryBrowserEntersDirectoryAndReturnsToParent() async throws {
    let rootURL = "https://svn.example.com/office/trunk"
    let reportsURL = rootURL + "/reports"
    let listing = RepositoryListingRecorder(entriesByURL: [
        rootURL: [makeRepositoryEntry("reports", kind: .directory)],
        reportsURL: [makeRepositoryEntry("2026.xlsx", kind: .file)],
    ])
    let state = RepositoryBrowserState(repositoryListing: listing, repositoryURL: rootURL)

    await state.browse()
    state.selectedEntryID = "reports"
    await state.enterSelectedDirectory()

    #expect(state.currentURL == reportsURL)
    #expect(state.entries.map(\.name) == ["2026.xlsx"])
    #expect(state.canNavigateUp)

    await state.navigateUp()

    #expect(state.currentURL == rootURL)
    #expect(state.entries.map(\.name) == ["reports"])
    #expect(!state.canNavigateUp)
    #expect(await listing.requestedURLs() == [rootURL, reportsURL, rootURL])
}

@MainActor
@Test func repositoryBrowserDistinguishesEmptyDirectoryAndFailures() async {
    let emptyURL = "https://svn.example.com/office/empty"
    let emptyListing = RepositoryListingRecorder(entriesByURL: [emptyURL: []])
    let emptyState = RepositoryBrowserState(
        repositoryListing: emptyListing,
        repositoryURL: emptyURL
    )

    await emptyState.browse()

    #expect(emptyState.phase == .loaded)
    #expect(emptyState.entries.isEmpty)

    let authenticationListing = RepositoryListingRecorder(error: SVNError.commandFailed(
        command: "svn list",
        message: "svn: E170001: Authentication required"
    ))
    let authenticationState = RepositoryBrowserState(
        repositoryListing: authenticationListing,
        repositoryURL: emptyURL
    )
    await authenticationState.browse()
    #expect(authenticationState.failure?.kind == .authentication)

    let invalidPathListing = RepositoryListingRecorder(error: SVNError.commandFailed(
        command: "svn list",
        message: "svn: E170013: Unable to connect\nsvn: E160013: path not found"
    ))
    let invalidPathState = RepositoryBrowserState(
        repositoryListing: invalidPathListing,
        repositoryURL: emptyURL
    )
    await invalidPathState.browse()
    #expect(invalidPathState.failure?.kind == .invalidURL)

    let connectionListing = RepositoryListingRecorder(error: SVNError.commandFailed(
        command: "svn list",
        message: "svn: E170013: Unable to connect to a repository at URL"
    ))
    let connectionState = RepositoryBrowserState(
        repositoryListing: connectionListing,
        repositoryURL: emptyURL
    )
    await connectionState.browse()
    #expect(connectionState.failure?.kind == .connection)

    let malformedURLState = RepositoryBrowserState(
        repositoryListing: emptyListing,
        repositoryURL: "not a repository URL"
    )
    await malformedURLState.browse()
    #expect(malformedURLState.failure?.kind == .invalidURL)
    #expect(await emptyListing.requestedURLs() == [emptyURL])
}

@MainActor
@Test func repositoryBrowserPreventsDuplicateRequests() async {
    let repositoryURL = "https://svn.example.com/office/trunk"
    let listing = RepositoryListingRecorder(
        entriesByURL: [repositoryURL: []],
        delay: .milliseconds(100)
    )
    let state = RepositoryBrowserState(
        repositoryListing: listing,
        repositoryURL: repositoryURL
    )

    let firstRequest = Task { await state.browse() }
    await Task.yield()
    await state.browse()
    await firstRequest.value

    #expect(await listing.requestedURLs() == [repositoryURL])
    #expect(state.phase == .loaded)
}

@MainActor
@Test func repositoryBrowserForwardsRevisionCredentialsAndCertificateOptions() async {
    let repositoryURL = "https://svn.example.com/office/trunk"
    let listing = RepositoryListingRecorder(entriesByURL: [repositoryURL: []])
    let state = RepositoryBrowserState(
        repositoryListing: listing,
        repositoryURL: repositoryURL,
        revision: "1845",
        credentials: SVNCredentials(username: "kim.office", password: "password"),
        allowUntrustedServerCertificate: true,
        allowedServerCertificateFailures: [.expired]
    )

    await state.browse()

    let request = await listing.requests().first
    #expect(request?.revision == "1845")
    #expect(request?.username == "kim.office")
    #expect(request?.password == "password")
    #expect(request?.allowUntrustedServerCertificate == true)
    #expect(request?.allowedServerCertificateFailures == [.expired])
}

@MainActor
@Test func repositoryBrowserSelectionStoresFullCheckoutURL() async {
    let rootURL = "https://svn.example.com/office/trunk"
    let listing = RepositoryListingRecorder(entriesByURL: [
        rootURL: [makeRepositoryEntry("reports", kind: .directory)],
    ])
    let state = RepositoryBrowserState(repositoryListing: listing, repositoryURL: rootURL)
    var recoveryState = ProjectRecoveryState()

    await state.browse()
    state.selectedEntryID = "reports"
    recoveryState.repositoryBrowseSelectedURL = state.checkoutURL

    #expect(recoveryState.repositoryBrowseSelectedURL == rootURL + "/reports")
}

@MainActor
@Test func demoRepositoryBrowserUsesOnlyInjectedListing() async {
    let unreachableURL = "https://must-not-run-svn.invalid/repository"
    let demoListing = RepositoryListingRecorder(entriesByURL: [unreachableURL: []])
    let state = RepositoryBrowserState(
        repositoryListing: demoListing,
        repositoryURL: unreachableURL
    )

    await state.browse()

    #expect(state.phase == .loaded)
    #expect(await demoListing.requestedURLs() == [unreachableURL])
}

private actor RepositoryListingRecorder: SVNRepositoryListing {
    struct Request: Sendable {
        let repositoryURL: String
        let revision: String?
        let username: String?
        let password: String?
        let allowUntrustedServerCertificate: Bool
        let allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    }

    private let entriesByURL: [String: [SVNRepositoryEntry]]
    private let error: SVNError?
    private let delay: Duration?
    private var recordedRequests: [Request] = []

    init(
        entriesByURL: [String: [SVNRepositoryEntry]] = [:],
        error: SVNError? = nil,
        delay: Duration? = nil
    ) {
        self.entriesByURL = entriesByURL
        self.error = error
        self.delay = delay
    }

    func repositoryEntries(
        at repositoryURL: String,
        revision: String?,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    ) async throws -> [SVNRepositoryEntry] {
        recordedRequests.append(Request(
            repositoryURL: repositoryURL,
            revision: revision,
            username: credentials?.username,
            password: credentials?.password,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ))
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        return entriesByURL[repositoryURL] ?? []
    }

    func requestedURLs() -> [String] {
        recordedRequests.map(\.repositoryURL)
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private func makeRepositoryEntry(
    _ name: String,
    kind: SVNRepositoryEntryKind
) -> SVNRepositoryEntry {
    SVNRepositoryEntry(
        name: name,
        kind: kind,
        size: kind == .file ? 100 : nil,
        lastChangedRevision: "1845",
        lastChangedAuthor: "kim.office",
        lastChangedDate: Date(timeIntervalSince1970: 1_768_173_600)
    )
}
