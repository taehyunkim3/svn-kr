import Foundation
import SVNCore
import Testing
@testable import SVNMac

/// 복구 프로젝트가 원본의 세부 인증서 허용값을 잃으면 복구 직후 새로고침부터
/// 같은 인증서를 다시 거부하거나 승인 화면을 또 요구한다.
@MainActor
@Test func recoveredProjectKeepsDetailedServerCertificateAllowances() async throws {
    let fixture = try RecoveryCertificateFixture(allowedFailures: [.expired])
    defer { fixture.remove() }

    let store = fixture.makeStore()
    store.pathRecoverySourceProjectID = fixture.project.id

    let succeeded = await store.recoverWorkingCopy(to: fixture.destination)

    #expect(succeeded, "복구가 실패했습니다: \(store.errorMessage ?? "-")")
    let recovered = try #require(store.projects.first(where: { $0.id != fixture.project.id }))
    #expect(recovered.allowedServerCertificateFailures == [.expired])
    #expect(recovered.allowsUntrustedServerCertificate == false)
}

/// 예전 Bool만 켜 둔 프로젝트도 복구본에서 같은 범위를 유지해야 한다.
@MainActor
@Test func recoveredProjectKeepsLegacyUntrustedCertificateAllowance() async throws {
    let fixture = try RecoveryCertificateFixture(allowedFailures: [], allowsUntrusted: true)
    defer { fixture.remove() }

    let store = fixture.makeStore()
    store.pathRecoverySourceProjectID = fixture.project.id

    let succeeded = await store.recoverWorkingCopy(to: fixture.destination)

    #expect(succeeded, "복구가 실패했습니다: \(store.errorMessage ?? "-")")
    let recovered = try #require(store.projects.first(where: { $0.id != fixture.project.id }))
    #expect(recovered.allowedServerCertificateFailures == SVNProject.legacyAllowedServerCertificateFailures)
}

private struct RecoveryCertificateFixture {
    let root: URL
    let source: URL
    let destination: URL
    let project: SVNProject
    private let executable: URL

    init(allowedFailures: Set<SVNServerCertificateFailure>, allowsUntrusted: Bool = false) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-certificate-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        destination = root.appendingPathComponent("recovered", isDirectory: true)
        executable = root.appendingPathComponent("fake-svn")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        command=
        for argument in "$@"; do
          case "$argument" in
            status|info|checkout) command=$argument ;;
          esac
        done
        if [ "$command" = info ]; then
          printf 'https://svn.example.test/project/trunk\\n'
          exit 0
        fi
        if [ "$command" = checkout ]; then
          exit 0
        fi
        if [ "$command" = status ]; then
          printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="10"/></entry></target></status>'
          exit 0
        fi
        exit 1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        project = SVNProject(
            name: "원본",
            path: source.path,
            allowsUntrustedServerCertificate: allowsUntrusted,
            allowedServerCertificateFailures: allowedFailures
        )
    }

    @MainActor
    func makeStore() -> ProjectStore {
        ProjectStore(
            client: SVNClient(
                executablePath: executable.path,
                configDirectoryPath: root.appendingPathComponent("svn-config").path
            ),
            credentialStore: RecoveryCertificateCredentialStore(),
            persistence: RecoveryCertificatePersistence(projects: [project]),
            projectAccessManager: RecoveryCertificateAccessManager(),
            projectPathChecker: RecoveryCertificatePathChecker(),
            settingsDefaults: UserDefaults(suiteName: "recovery-certificate-\(UUID().uuidString)")!,
            updateBadgeRefreshInterval: nil
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct RecoveryCertificateCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct RecoveryCertificatePersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private final class RecoveryCertificateAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

private struct RecoveryCertificatePathChecker: ProjectPathChecking {
    func directoryExists(at _: String) -> Bool { true }
}
