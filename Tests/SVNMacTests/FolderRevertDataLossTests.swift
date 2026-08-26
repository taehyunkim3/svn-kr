import Foundation
import SVNCore
import Testing
@testable import SVNMac

/// `svn revert --depth infinity`는 복사로 추가한 폴더를 디스크에서 통째로 지웁니다.
/// 그 안의 버전관리되지 않은 파일은 저장소 이력에도 없으므로 복구본이 없으면 영구 손실입니다.
/// 확인창은 개수만이 아니라 사라질 경로를 보여줘야 합니다.
@MainActor
@Test func folderRevertListsSubtreePathsAndPreservesThemBeforeSVNDeletesTheFolder() async throws {
    let fixture = try FolderRevertFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    await store.refresh()

    let entry = try #require(
        store.statuses.first { $0.path.precomposedStringWithCanonicalMapping == "사본" }
    )
    #expect(entry.nodeKind == .directory)
    store.requestRevert(entry)
    let request = try #require(store.revertRequest)
    let impact = try #require(store.revertImpact(for: request))
    // 미버전 디렉터리는 `svn status`가 항목 하나로만 보고하므로 펼쳐서 세야 합니다.
    #expect(precomposedPaths(impact.unversionedPaths) == [
        "사본/미버전메모.txt",
        "사본/임시/초안.txt",
    ])
    #expect(precomposedPaths(impact.uncommittedPaths) == ["사본/보고서.xlsx"])

    await store.confirmRevert(request)

    #expect(store.errorMessage == nil)
    // 여기까지는 SVN 동작입니다. 앱이 막을 수 없습니다.
    #expect(!FileManager.default.fileExists(
        atPath: fixture.workingCopy.appendingPathComponent("사본").path
    ))
    let preserved = try fixture.preservedFileContents()
    #expect(preserved.contains(fixture.unversionedBytes))
    #expect(preserved.contains(fixture.draftBytes))
    #expect(preserved.contains(fixture.editedReportBytes))
}

/// 파일 하나를 되돌릴 때는 확인창 경로가 곧 사라지는 것 전부입니다.
/// 목록도 만들지 않고 복구본도 만들지 않습니다.
@MainActor
@Test func singleFileRevertKeepsExistingBehaviourWithoutSubtreeScan() async throws {
    let fixture = try FolderRevertFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    await store.refresh()
    let entry = try #require(
        store.statuses.first { $0.path.precomposedStringWithCanonicalMapping == "공유/보고서.xlsx" }
    )

    store.requestRevert(entry)
    let request = try #require(store.revertRequest)
    #expect(store.revertImpact(for: request) == nil)

    await store.confirmRevert(request)

    #expect(store.errorMessage == nil)
    #expect(
        try Data(contentsOf: fixture.workingCopy.appendingPathComponent("공유/보고서.xlsx"))
            == fixture.committedReportBytes
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.backupRoot.path))
}

@Test func revertConfirmationListsPathsWithTheSharedListedPathLimit() throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SVNMac/RevertConfirmation.swift"),
        encoding: .utf8
    )
    #expect(source.contains("AppLayout.treeConflictRestoreListedPathLimit"))
    #expect(source.contains("store.revertImpact(for: request)"))
}

private func precomposedPaths(_ paths: [String]) -> [String] {
    paths.map { $0.precomposedStringWithCanonicalMapping }.sorted()
}

/// 커밋한 폴더 하나에 미버전 파일과 수정 파일을 두고, 별도로 복사만 예약한 폴더를 만듭니다.
private final class FolderRevertFixture {
    let root: URL
    let workingCopy: URL
    let backupRoot: URL
    let client: SVNClient
    let committedReportBytes = Data("커밋한 보고서\n".utf8)
    let editedReportBytes = Data("편집 중\n".utf8)
    let draftBytes = Data("초안\n".utf8)
    let unversionedBytes = Data("복사한 폴더 안의 미버전 메모\n".utf8)
    private let svnPath: String

    init() throws {
        let fileManager = FileManager.default
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("folder-revert-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path])
        let repositoryURL = repository.absoluteString + "trunk"
        _ = try Self.run(svnPath, ["mkdir", repositoryURL, "-m", "trunk"])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )

        try write(committedReportBytes, relativePath: "공유/보고서.xlsx")
        _ = try Self.run(svnPath, ["add", "공유"], currentDirectory: workingCopy)
        _ = try Self.run(svnPath, ["commit", "-m", "공유 폴더"], currentDirectory: workingCopy)
        // 커밋하지 않은 수정과 미버전 파일을 함께 둡니다.
        try write(editedReportBytes, relativePath: "공유/보고서.xlsx")
        try write(draftBytes, relativePath: "공유/임시/초안.txt")
        // 복사만 예약한 폴더는 되돌리면 디스크에서 사라집니다.
        _ = try Self.run(svnPath, ["copy", "공유", "사본"], currentDirectory: workingCopy)
        try write(unversionedBytes, relativePath: "사본/미버전메모.txt")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func preservedFileContents() throws -> [Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: backupRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var contents: [Data] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            contents.append(try Data(contentsOf: url))
        }
        return contents
    }

    @MainActor
    func makeStore() -> ProjectStore {
        let project = SVNProject(name: "폴더 되돌리기", path: workingCopy.path)
        return ProjectStore(
            client: client,
            credentialStore: FolderRevertCredentialStore(),
            persistence: FolderRevertPersistence(projects: [project]),
            projectAccessManager: FolderRevertAccessManager(),
            conflictFileService: ConflictFileService(backupRootURL: backupRoot),
            projectPathChecker: FolderRevertPathChecker(),
            volumeNormalizationProbe: FolderRevertVolumeProbe(),
            settingsDefaults: UserDefaults(suiteName: "folder-revert-\(UUID().uuidString)")!,
            updateBadgeRefreshInterval: nil
        )
    }

    private func write(_ data: Data, relativePath: String) throws {
        let destination = workingCopy.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw FolderRevertCommandError(
                command: ([executable] + arguments).joined(separator: " "),
                output: text
            )
        }
        return text
    }
}

private struct FolderRevertCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String
    var description: String { "\(command)\n\(output)" }
}

private struct FolderRevertCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct FolderRevertPersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private final class FolderRevertAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

private struct FolderRevertPathChecker: ProjectPathChecking {
    func directoryExists(at _: String) -> Bool { true }
}

private actor FolderRevertVolumeProbe: VolumeNormalizationProbing {
    func preservesPrecomposedFilenames(at _: String) async -> Bool? { true }
}
