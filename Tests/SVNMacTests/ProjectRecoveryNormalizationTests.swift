import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func pathRecoveryRegistersCurrentProjectThroughNormalizationProbePath() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac/ProjectStore+Recovery.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let projectStoreSource = try String(
        contentsOf: sourceURL.deletingLastPathComponent().appendingPathComponent("ProjectStore.swift"),
        encoding: .utf8
    )

    #expect(source.contains("registerRecoveredCheckout(recoveredProject)"))
    #expect(projectStoreSource.contains("func registerRecoveredCheckout(_ project: SVNProject)"))
    #expect(projectStoreSource.contains("probeFilenameNormalization(for: project)"))
}

@MainActor
@Test func recoveredCheckoutRegistrationRunsFilenameNormalizationProbe() async {
    let probe = RecoveryNormalizationProbe(result: false)
    let store = ProjectStore(
        client: SVNClient(),
        credentialStore: RecoveryNormalizationCredentialStore(),
        persistence: RecoveryNormalizationPersistence(),
        projectAccessManager: RecoveryNormalizationAccessManager(),
        projectPathChecker: RecoveryNormalizationPathChecker(),
        volumeNormalizationProbe: probe,
        settingsDefaults: UserDefaults(suiteName: "recovery-normalization-\(UUID().uuidString)")!,
        updateBadgeRefreshInterval: nil
    )
    let project = SVNProject(name: "recovered", path: "/tmp/recovered-on-nfd-volume")

    store.registerRecoveredCheckout(project)
    await store.waitForFilenameNormalizationProbes()

    #expect(await probe.probedPaths == [project.path])
    #expect(store.filenameNormalizationWarningProjectIDs == [project.id])
}

private struct RecoveryNormalizationCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct RecoveryNormalizationPersistence: ProjectPersisting {
    func loadProjects() -> [SVNProject] { [] }
    func saveProjects(_: [SVNProject]) {}
}

private final class RecoveryNormalizationAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

private struct RecoveryNormalizationPathChecker: ProjectPathChecking {
    func directoryExists(at _: String) -> Bool { true }
}

private actor RecoveryNormalizationProbe: VolumeNormalizationProbing {
    let result: Bool?
    private(set) var probedPaths: [String] = []

    init(result: Bool?) {
        self.result = result
    }

    func preservesPrecomposedFilenames(at directoryPath: String) -> Bool? {
        probedPaths.append(directoryPath)
        return result
    }
}
