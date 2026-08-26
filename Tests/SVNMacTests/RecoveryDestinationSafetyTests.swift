import Foundation
import SVNCore
import Testing
@testable import SVNMac

/// 폴더 선택 창은 현재 작업 폴더에서 열린다. 그 안에 새 폴더를 만들어 복구하면
/// 새 체크아웃이 원본의 미등록 항목으로 잡혀 저장소 전체가 중첩 복사된다.
@MainActor
@Test func recoveryRejectsDestinationInsideCurrentWorkingFolder() async throws {
    let fixture = try RecoveryDestinationFixture()
    defer { fixture.remove() }
    let destination = fixture.workingFolder.appendingPathComponent("복구", isDirectory: true)

    let store = fixture.makeStore()
    store.pathRecoverySourceProjectID = fixture.project.id

    let succeeded = await store.recoverWorkingCopy(to: destination)

    #expect(!succeeded)
    #expect(store.errorMessage == AppLanguage.current.localized(
        .ui.recovery.recoveryFolderMustBeOutsideCurrentWorkingFolder
    ))
    #expect(store.projects.count == 1)
    #expect(!FileManager.default.fileExists(atPath: fixture.commandLog.path))
}

/// 상위 폴더로 복구하면 체크아웃이 원본을 덮거나 지울 수 있다.
@MainActor
@Test func recoveryRejectsDestinationThatContainsCurrentWorkingFolder() async throws {
    let fixture = try RecoveryDestinationFixture()
    defer { fixture.remove() }

    let store = fixture.makeStore()
    store.pathRecoverySourceProjectID = fixture.project.id

    let succeeded = await store.recoverWorkingCopy(to: fixture.root)

    #expect(!succeeded)
    #expect(store.errorMessage == AppLanguage.current.localized(
        .ui.recovery.recoveryFolderMustBeOutsideCurrentWorkingFolder
    ))
    #expect(!FileManager.default.fileExists(atPath: fixture.commandLog.path))
}

@MainActor
@Test func recoveryAllowsSiblingDestinationWithSharedNamePrefix() throws {
    let fixture = try RecoveryDestinationFixture()
    defer { fixture.remove() }
    let sibling = fixture.root.appendingPathComponent("작업-복구본", isDirectory: true)

    #expect(ProjectStore.recoveryDestinationIsOutside(
        sourcePath: fixture.workingFolder.path,
        destination: sibling
    ))
    #expect(!ProjectStore.recoveryDestinationIsOutside(
        sourcePath: fixture.workingFolder.path,
        destination: fixture.workingFolder.appendingPathComponent("안쪽", isDirectory: true)
    ))
    // APFS는 대소문자와 유니코드 정규화를 무시하므로 같은 폴더를 다르게 적어도 막아야 한다.
    #expect(!ProjectStore.recoveryDestinationIsOutside(
        sourcePath: fixture.workingFolder.path,
        destination: URL(
            fileURLWithPath: fixture.workingFolder.path.decomposedStringWithCanonicalMapping,
            isDirectory: true
        )
    ))
}

private struct RecoveryDestinationFixture {
    let root: URL
    let workingFolder: URL
    let commandLog: URL
    let project: SVNProject
    private let executable: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-destination-\(UUID().uuidString)", isDirectory: true)
        workingFolder = root.appendingPathComponent("작업", isDirectory: true)
        commandLog = root.appendingPathComponent("command-log")
        executable = root.appendingPathComponent("fake-svn")
        try FileManager.default.createDirectory(at: workingFolder, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(commandLog.path)'
        exit 1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        project = SVNProject(name: "작업", path: workingFolder.path)
    }

    @MainActor
    func makeStore() -> ProjectStore {
        ProjectStore(
            client: SVNClient(executablePath: executable.path),
            credentialStore: RecoveryDestinationCredentialStore(),
            persistence: RecoveryDestinationPersistence(projects: [project]),
            projectAccessManager: RecoveryDestinationAccessManager(),
            projectPathChecker: RecoveryDestinationPathChecker(),
            settingsDefaults: UserDefaults(suiteName: "recovery-destination-\(UUID().uuidString)")!,
            updateBadgeRefreshInterval: nil
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct RecoveryDestinationCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct RecoveryDestinationPersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private final class RecoveryDestinationAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

private struct RecoveryDestinationPathChecker: ProjectPathChecking {
    func directoryExists(at _: String) -> Bool { true }
}
