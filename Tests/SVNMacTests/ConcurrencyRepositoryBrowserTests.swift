import Foundation
import SVNCore
import Testing
@testable import SVNMac

@MainActor
@Test func repositoryBrowserCancellationStopsButtonStartedRequest() async throws {
    let probe = RepositoryBrowserCancellationProbe()
    let state = RepositoryBrowserState(
        repositoryEntries: { url, revision, credentials, allowsUntrusted, failures in
            try await probe.load(
                url,
                revision: revision,
                credentials: credentials,
                allowsUntrusted: allowsUntrusted,
                failures: failures
            )
        },
        repositoryURL: "https://svn.example.com/office/trunk"
    )

    let task = state.beginBrowse()
    await probe.waitUntilStarted()
    state.cancelLoading()
    await task.value

    #expect(await probe.didObserveCancellation())
    #expect(state.phase == .idle)
}

@Test func repositoryBrowserViewCancelsManagedRequestWhenDismissed() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent("Sources/SVNMac/RepositoryBrowserView.swift"),
        encoding: .utf8
    )

    #expect(source.contains(".onDisappear { state.cancelLoading() }"))
    #expect(source.contains("state.beginBrowse()"))
    #expect(source.contains("state.beginRefresh()"))
    #expect(!source.contains("Task { await state.browse() }"))
    #expect(!source.contains("Task { await state.refresh() }"))
}

private actor RepositoryBrowserCancellationProbe {
    private var started = false
    private var cancellationObserved = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func load(
        _ repositoryURL: String,
        revision: String?,
        credentials: SVNCredentials?,
        allowsUntrusted: Bool,
        failures: Set<SVNServerCertificateFailure>
    ) async throws -> [SVNRepositoryEntry] {
        _ = (repositoryURL, revision, credentials, allowsUntrusted, failures)
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            cancellationObserved = Task.isCancelled
            throw error
        }
        return []
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func didObserveCancellation() -> Bool {
        cancellationObserved
    }
}
