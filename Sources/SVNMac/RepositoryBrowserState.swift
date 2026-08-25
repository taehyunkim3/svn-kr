import Foundation
import Observation
import SVNCore

typealias RepositoryEntriesLoading = @Sendable (
    _ repositoryURL: String,
    _ revision: String?,
    _ credentials: SVNCredentials?,
    _ allowUntrustedServerCertificate: Bool,
    _ allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
) async throws -> [SVNRepositoryEntry]

struct RepositoryBrowserConnectionSettings {
    let credentials: SVNCredentials?
    let allowUntrustedServerCertificate: Bool
    let allowedServerCertificateFailures: Set<SVNServerCertificateFailure>

    init(
        username: String,
        password: String,
        allowsUntrustedServerCertificate: Bool
    ) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        credentials = username.isEmpty
            ? nil
            : SVNCredentials(username: username, password: password.isEmpty ? nil : password)
        allowUntrustedServerCertificate = allowsUntrustedServerCertificate
        allowedServerCertificateFailures = allowsUntrustedServerCertificate
            ? SVNProject.legacyAllowedServerCertificateFailures
            : []
    }
}

enum RepositoryBrowserPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(RepositoryBrowserFailure)
}

struct RepositoryBrowserFailure: Equatable {
    enum Kind: Equatable {
        case authentication
        case invalidURL
        case connection
        case other
    }

    let kind: Kind
    let details: String
}

@MainActor
@Observable
final class RepositoryBrowserState {
    var repositoryURLInput: String
    var revisionInput: String
    var selectedEntryID: SVNRepositoryEntry.ID?
    private(set) var rootURL: String?
    private(set) var currentURL = ""
    private(set) var entries: [SVNRepositoryEntry] = []
    private(set) var phase = RepositoryBrowserPhase.idle

    @ObservationIgnored private let loadRepositoryEntries: RepositoryEntriesLoading
    @ObservationIgnored private let credentials: SVNCredentials?
    @ObservationIgnored private let allowUntrustedServerCertificate: Bool
    @ObservationIgnored private let allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    convenience init(
        repositoryListing: any SVNClientServing,
        repositoryURL: String,
        revision: String? = nil,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) {
        self.init(
            repositoryEntries: { repositoryURL, revision, credentials, allowsUntrusted, failures in
                try await repositoryListing.repositoryEntries(
                    at: repositoryURL,
                    revision: revision,
                    credentials: credentials,
                    allowUntrustedServerCertificate: allowsUntrusted,
                    allowedServerCertificateFailures: failures
                )
            },
            repositoryURL: repositoryURL,
            revision: revision,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
    }

    init(
        repositoryEntries: @escaping RepositoryEntriesLoading,
        repositoryURL: String,
        revision: String? = nil,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) {
        loadRepositoryEntries = repositoryEntries
        repositoryURLInput = repositoryURL
        revisionInput = revision ?? ""
        self.credentials = credentials
        self.allowUntrustedServerCertificate = allowUntrustedServerCertificate
        self.allowedServerCertificateFailures = allowedServerCertificateFailures
    }

    var isLoading: Bool { phase == .loading }

    var failure: RepositoryBrowserFailure? {
        guard case let .failed(failure) = phase else { return nil }
        return failure
    }

    var canNavigateUp: Bool {
        guard let rootURL else { return false }
        return !currentURL.isEmpty && currentURL != rootURL
    }

    var selectedEntry: SVNRepositoryEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var checkoutURL: String? {
        guard phase == .loaded else { return nil }
        guard let selectedEntry else { return currentURL.isEmpty ? nil : currentURL }
        guard selectedEntry.kind == .directory else { return nil }
        return Self.appending(selectedEntry.name, to: currentURL)
    }

    @discardableResult
    func beginBrowse() -> Task<Void, Never> {
        startLoading { state in await state.browse() }
    }

    @discardableResult
    func beginRefresh() -> Task<Void, Never> {
        startLoading { state in await state.refresh() }
    }

    @discardableResult
    func beginEnterSelectedDirectory() -> Task<Void, Never> {
        startLoading { state in await state.enterSelectedDirectory() }
    }

    @discardableResult
    func beginNavigateUp() -> Task<Void, Never> {
        startLoading { state in await state.navigateUp() }
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func startLoading(
        _ operation: @escaping @MainActor (RepositoryBrowserState) async -> Void
    ) -> Task<Void, Never> {
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await operation(self)
        }
        loadTask = task
        return task
    }

    func browse() async {
        guard !isLoading else { return }
        guard let normalizedURL = Self.normalizedRepositoryURL(repositoryURLInput) else {
            entries = []
            selectedEntryID = nil
            phase = .failed(RepositoryBrowserFailure(
                kind: .invalidURL,
                details: repositoryURLInput
            ))
            return
        }
        rootURL = normalizedURL
        currentURL = normalizedURL
        await loadCurrentDirectory()
    }

    func refresh() async {
        guard !currentURL.isEmpty else {
            await browse()
            return
        }
        await loadCurrentDirectory()
    }

    func enterSelectedDirectory() async {
        guard let selectedEntry, selectedEntry.kind == .directory else { return }
        await navigate(to: Self.appending(selectedEntry.name, to: currentURL))
    }

    func navigateUp() async {
        guard canNavigateUp,
              let parentURL = Self.parent(of: currentURL) else { return }
        await navigate(to: parentURL)
    }

    private func navigate(to repositoryURL: String?) async {
        guard !isLoading, let repositoryURL else { return }
        currentURL = repositoryURL
        await loadCurrentDirectory()
    }

    private func loadCurrentDirectory() async {
        guard !isLoading, !currentURL.isEmpty else { return }
        phase = .loading
        entries = []
        selectedEntryID = nil
        do {
            let revision = revisionInput.trimmingCharacters(in: .whitespacesAndNewlines)
            entries = try await loadRepositoryEntries(
                currentURL,
                revision.isEmpty ? nil : revision,
                credentials,
                allowUntrustedServerCertificate,
                allowedServerCertificateFailures
            ).sorted(by: Self.sortEntries)
            phase = .loaded
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(Self.failure(for: error))
        }
    }

    private static func sortEntries(_ lhs: SVNRepositoryEntry, _ rhs: SVNRepositoryEntry) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .directory }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func normalizedRepositoryURL(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty else { return nil }
        if scheme == "file" {
            guard !components.path.isEmpty else { return nil }
        } else {
            guard components.host?.isEmpty == false else { return nil }
        }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }
        return removingTrailingSlash(from: url.absoluteString)
    }

    private static func appending(_ name: String, to repositoryURL: String) -> String? {
        guard let url = URL(string: repositoryURL) else { return nil }
        return removingTrailingSlash(
            from: url.appendingPathComponent(name, isDirectory: false).absoluteString
        )
    }

    private static func parent(of repositoryURL: String) -> String? {
        guard let url = URL(string: repositoryURL) else { return nil }
        return removingTrailingSlash(from: url.deletingLastPathComponent().absoluteString)
    }

    private static func removingTrailingSlash(from value: String) -> String {
        guard value.hasSuffix("/"),
              let components = URLComponents(string: value),
              components.path != "/" else { return value }
        return String(value.dropLast())
    }

    private static func failure(for error: Error) -> RepositoryBrowserFailure {
        let details: String
        if case let SVNError.commandFailed(_, message) = error {
            details = message
        } else {
            details = error.localizedDescription
        }
        let kind: RepositoryBrowserFailure.Kind
        if SVNClient.isAuthenticationError(error) {
            kind = .authentication
        } else if details.contains("E160013")
            || details.contains("E170000")
            || details.contains("E125002")
            || details.contains("E200009") {
            kind = .invalidURL
        } else if SVNClient.isRepositoryConnectionError(error) {
            kind = .connection
        } else {
            kind = .other
        }
        return RepositoryBrowserFailure(kind: kind, details: details)
    }
}
