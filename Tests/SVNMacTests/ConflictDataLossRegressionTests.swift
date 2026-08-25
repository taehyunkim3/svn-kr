import Foundation
import SVNCore
import Testing
@testable import SVNMac

// 감사 A 2번: 트리 충돌의 "서버 버전으로 파일 복구"가 하위 트리를 백업 없이 지우던 회귀 테스트입니다.
// 실제 `svn`을 실행합니다. `svn revert --depth infinity`의 실제 동작이 재현 조건이라
// 가짜 클라이언트로는 같은 사고를 다시 잡아낼 수 없습니다.

@MainActor
@Test func directoryTreeConflictRestoreBacksUpUnversionedFilesBeforeRevert() async throws {
    let fixture = try DirectoryTreeConflictFixture()
    defer { fixture.remove() }

    let store = fixture.makeStore()
    // 디스크가 한글 이름을 자모 분리로 저장할 수 있으므로 앱이 목록에서 넘기는 표기를 그대로 씁니다.
    await store.prepareConflictResolution(for: try fixture.onDiskConflictedDirectory())

    let session = try #require(store.activeTreeConflictSession)
    #expect(store.activeConflictSession == nil)
    #expect(store.recoveryState.propertyConflictSession == nil)

    // 확인창이 개수만이 아니라 경로를 보여줄 수 있어야 합니다.
    // 미버전 디렉터리는 `svn status` 가 항목 하나로만 보고하므로 펼쳐서 세야 합니다.
    #expect(precomposed(session.restoreImpact.unversionedPaths) == [
        "문서/새폴더/견적.hwp",
        "문서/신규계약서.xlsx",
    ])
    #expect(precomposed(session.restoreImpact.uncommittedPaths) == ["문서/계획.txt"])

    await store.resolveActiveTreeConflict(using: .restoreServerVersion)

    #expect(store.errorMessage == nil)
    #expect(store.activeTreeConflictSession == nil)
    // `svn revert --depth infinity` 는 하위 트리를 통째로 지웁니다. 여기까지는 SVN 동작입니다.
    #expect(!FileManager.default.fileExists(
        atPath: fixture.workingCopy.appendingPathComponent(fixture.conflictedDirectory).path
    ))

    // 저장소에 없던 파일은 복구본이 없으면 영구 손실입니다.
    let preserved = try regularFileContents(under: fixture.backupRoot)
    #expect(preserved.contains(fixture.contractBytes))
    #expect(preserved.contains(fixture.quoteBytes))
    #expect(preserved.contains(fixture.editedPlanBytes))
}

// MARK: - 순수 로직

@Test func restoreScanExpandsUnversionedDirectoriesAndSkipsVersionedDirectories() {
    let statuses = [
        SVNStatusEntry(path: "문서", item: .added),
        SVNStatusEntry(path: "문서/계획.txt", item: .modified),
        SVNStatusEntry(path: "문서/신규계약서.xlsx", item: .unversioned),
        SVNStatusEntry(path: "문서/새폴더", item: .unversioned),
        SVNStatusEntry(path: "다른폴더/무관.txt", item: .unversioned),
    ]
    let impact = TreeConflictRestoreScan.impact(
        target: "문서",
        statuses: statuses,
        containedFilePaths: { path in
            switch path {
            case "문서": ["문서/계획.txt"]
            case "문서/새폴더": ["문서/새폴더/견적.hwp", "문서/새폴더/더깊이/메모.hwp"]
            default: []
            }
        }
    )

    #expect(impact.unversionedPaths == [
        "문서/새폴더/견적.hwp",
        "문서/새폴더/더깊이/메모.hwp",
        "문서/신규계약서.xlsx",
    ])
    #expect(impact.uncommittedPaths == ["문서/계획.txt"])
    #expect(!impact.entries.contains { $0.relativePath == "문서" })
    #expect(!impact.entries.contains { $0.relativePath == "다른폴더/무관.txt" })
}

// MARK: - 도우미

private func precomposed(_ paths: [String]) -> [String] {
    paths.map { $0.precomposedStringWithCanonicalMapping }
}

private func regularFileContents(under directory: URL) throws -> [Data] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
    ) else { return [] }
    var contents: [Data] = []
    for case let url as URL in enumerator {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            continue
        }
        contents.append(try Data(contentsOf: url))
    }
    return contents
}

private class DataLossFixture {
    let root: URL
    let repository: URL
    let publisherRoot: URL
    let workingCopyRoot: URL
    let backupRoot: URL
    let projectID = UUID()
    let svnPath: String
    let svnadminPath: String
    let client: SVNClient

    var publisher: URL { publisherRoot }
    var workingCopy: URL { workingCopyRoot }

    init(name: String) throws {
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn",
            "/usr/local/bin/svn",
            "/usr/bin/svn",
        ]))
        svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin",
            "/usr/local/bin/svnadmin",
            "/usr/bin/svnadmin",
        ]))
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("svn-data-loss-\(name)-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        publisherRoot = root.appendingPathComponent("publisher", isDirectory: true)
        workingCopyRoot = root.appendingPathComponent("working", isDirectory: true)
        backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path])
    }

    var repositoryURL: String {
        URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func runSVN(_ arguments: [String]) throws -> String {
        try Self.run(svnPath, arguments)
    }

    @MainActor
    func makeStore() -> ProjectStore {
        let project = SVNProject(name: "데이터 손실 회귀", path: workingCopy.path)
        return ProjectStore(
            client: client,
            credentialStore: DataLossCredentialStore(),
            persistence: DataLossProjectPersistence(projects: [project]),
            projectAccessManager: DataLossProjectAccessManager(),
            conflictFileService: ConflictFileService(backupRootURL: backupRoot),
            workspaceOpener: DataLossWorkspaceOpener(),
            projectPathChecker: DataLossProjectPathChecker(),
            volumeNormalizationProbe: DataLossVolumeNormalizationProbe(),
            settingsDefaults: UserDefaults(suiteName: "data-loss-\(UUID().uuidString)")!,
            isDemoMode: true,
            updateBadgeRefreshInterval: nil
        )
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    static func run(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw DataLossCommandError(
                command: ([executablePath] + arguments).joined(separator: " "),
                output: text
            )
        }
        return text
    }
}

/// 서버가 폴더를 지운 뒤 로컬에 미커밋 편집과 미버전 문서가 남은 디렉터리 트리 충돌입니다.
private final class DirectoryTreeConflictFixture: DataLossFixture {
    let conflictedDirectory = "문서"
    let editedPlanBytes = Data("내가 고친 계획\n".utf8)
    let contractBytes = Data("한 번도 커밋한 적 없는 계약서\n".utf8)
    let quoteBytes = Data("한 번도 커밋한 적 없는 견적\n".utf8)

    /// 작업 복사본이 실제로 들고 있는 표기(NFC 또는 NFD)를 그대로 돌려줍니다.
    func onDiskConflictedDirectory() throws -> String {
        let names = try FileManager.default.contentsOfDirectory(atPath: workingCopy.path)
        return try #require(names.first { name in
            name.precomposedStringWithCanonicalMapping == conflictedDirectory
        })
    }

    init() throws {
        try super.init(name: "tree")
        let fileManager = FileManager.default
        _ = try runSVN(["checkout", repositoryURL, publisher.path])
        let publishedDirectory = publisher.appendingPathComponent(conflictedDirectory)
        try fileManager.createDirectory(
            at: publishedDirectory.appendingPathComponent("하위"),
            withIntermediateDirectories: true
        )
        try Data("계획\n".utf8).write(to: publishedDirectory.appendingPathComponent("계획.txt"))
        try Data("세부\n".utf8).write(
            to: publishedDirectory.appendingPathComponent("하위/세부.txt")
        )
        _ = try runSVN(["add", publishedDirectory.path])
        _ = try runSVN(["commit", publisher.path, "-m", "initial"])
        _ = try runSVN(["checkout", repositoryURL, workingCopy.path])

        _ = try runSVN(["delete", publishedDirectory.path])
        _ = try runSVN(["commit", publisher.path, "-m", "server removes folder"])

        let localDirectory = workingCopy.appendingPathComponent(conflictedDirectory)
        try editedPlanBytes.write(to: localDirectory.appendingPathComponent("계획.txt"))
        try contractBytes.write(to: localDirectory.appendingPathComponent("신규계약서.xlsx"))
        try fileManager.createDirectory(
            at: localDirectory.appendingPathComponent("새폴더"),
            withIntermediateDirectories: true
        )
        try quoteBytes.write(to: localDirectory.appendingPathComponent("새폴더/견적.hwp"))
        _ = try runSVN(["update", "--non-interactive", "--accept", "postpone", workingCopy.path])
    }
}

private struct DataLossCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String

    var description: String { "Command failed: \(command)\n\(output)" }
}

private struct DataLossCredentialStore: CredentialStoring {
    func password(for projectID: UUID) throws -> String? { nil }
    func setPassword(_ password: String, for projectID: UUID) throws {}
    func deletePassword(for projectID: UUID) throws {}
}

private struct DataLossProjectPersistence: ProjectPersisting {
    let projects: [SVNProject]

    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_ projects: [SVNProject]) {}
}

private final class DataLossProjectAccessManager: ProjectAccessManaging {
    func makeBookmark(for url: URL) throws -> Data { Data() }
    func restoreAccess(for projects: inout [SVNProject]) {}
    func beginAccessing(_ url: URL, for projectID: SVNProject.ID) {}
    func endAccessing(projectID: SVNProject.ID) {}
    func endAccessing(url: URL) {}
}

@MainActor
private struct DataLossWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) -> Bool { true }
}

private struct DataLossProjectPathChecker: ProjectPathChecking {
    func directoryExists(at path: String) -> Bool { true }
}

private struct DataLossVolumeNormalizationProbe: VolumeNormalizationProbing {
    func preservesPrecomposedFilenames(at directoryPath: String) async -> Bool? { nil }
}
