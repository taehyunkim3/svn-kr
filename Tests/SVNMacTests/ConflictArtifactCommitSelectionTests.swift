import Foundation
import SVNCore
import Testing
@testable import SVNMac

/// `svn update`가 충돌을 남기면 `.mine` / `.rN` / `.prej`가 미버전 파일로 나타납니다.
/// 충돌을 해결하면 SVN이 지우는 파일이므로 저장소에 올릴 대상이 아닙니다.
@Test func conflictArtifactsAreHiddenFromChangesAndSelectAll() throws {
    let entries = [
        SVNStatusEntry(path: "문서.txt", item: .conflicted, revision: "3", nodeKind: .file, propertyState: .conflicted),
        SVNStatusEntry(path: "문서.txt.mine", item: .unversioned, nodeKind: .file),
        SVNStatusEntry(path: "문서.txt.r2", item: .unversioned, nodeKind: .file),
        SVNStatusEntry(path: "문서.txt.r3", item: .unversioned, nodeKind: .file),
        SVNStatusEntry(path: "문서.txt.prej", item: .unversioned, nodeKind: .file),
        SVNStatusEntry(path: "새자료.xlsx", item: .unversioned, nodeKind: .file),
    ]

    let visible = TemporaryFilePolicy.visibleEntries(entries, hideTemporaryFiles: false)
    #expect(visible.map(\.path) == ["문서.txt", "새자료.xlsx"])
    #expect(
        TemporaryFilePolicy.commitEligibleEntries(entries, hideTemporaryFiles: false).map(\.path)
            == ["새자료.xlsx"]
    )
    #expect(
        TemporaryFilePolicy.automaticallySelectedEntries(entries).map(\.path) == ["새자료.xlsx"]
    )
}

/// 속성만 충돌하면 항목 상태는 `conflicted`가 아닙니다. `.prej`는 그때도 걸러야 합니다.
@Test func propertyOnlyConflictArtifactIsAlsoExcluded() throws {
    let entries = [
        SVNStatusEntry(path: "예산.xlsx", item: .modified, revision: "5", nodeKind: .file, propertyState: .conflicted),
        SVNStatusEntry(path: "예산.xlsx.prej", item: .unversioned, nodeKind: .file),
    ]

    #expect(
        TemporaryFilePolicy.visibleEntries(entries, hideTemporaryFiles: false).map(\.path)
            == ["예산.xlsx"]
    )
    #expect(TemporaryFilePolicy.automaticallySelectedEntries(entries).isEmpty)
}

/// 충돌이 없으면 같은 이름이라도 사용자 파일입니다. 목록에서 지우면 안 됩니다.
@Test func artifactNamedFilesSurviveWhenNoConflictExists() throws {
    let entries = [
        SVNStatusEntry(path: "메모.mine", item: .unversioned, nodeKind: .file),
        SVNStatusEntry(path: "보고서.r2", item: .unversioned, nodeKind: .file),
        SVNStatusEntry(path: "설정.prej", item: .added, revision: "-1", nodeKind: .file),
    ]

    #expect(
        TemporaryFilePolicy.visibleEntries(entries, hideTemporaryFiles: false).map(\.path)
            == entries.map(\.path)
    )
    #expect(
        TemporaryFilePolicy.automaticallySelectedEntries(entries).map(\.path) == entries.map(\.path)
    )
}

/// 자모 분리로 저장된 이름도 같은 파일입니다. 정규화해 비교해야 걸러집니다.
@Test func decomposedArtifactNameMatchesConflictedBasePath() throws {
    let base = "보고서.txt".precomposedStringWithCanonicalMapping
    let entries = [
        SVNStatusEntry(path: base, item: .conflicted, revision: "9", nodeKind: .file),
        SVNStatusEntry(
            path: "보고서.txt".decomposedStringWithCanonicalMapping + ".mine",
            item: .unversioned,
            nodeKind: .file
        ),
    ]

    #expect(TemporaryFilePolicy.visibleEntries(entries, hideTemporaryFiles: false).map(\.path) == [base])
}

/// 실제 SVN 충돌에서 스냅샷 경로가 산출물을 그대로 넘기는지 확인합니다.
/// `SVNXMLParser.statuses`는 `.mine`과 `.rN`을 거르지만 스냅샷은 거르지 않습니다.
@MainActor
@Test func realSVNConflictArtifactsNeverEnterCommitSelection() async throws {
    let fixture = try ConflictArtifactFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()

    await store.refresh()

    let rawPaths = store.statuses.map { $0.path.precomposedStringWithCanonicalMapping }.sorted()
    // 스냅샷은 산출물을 그대로 넘깁니다. 필터가 없으면 여기까지 올라옵니다.
    // `.mine`은 SVN 버전에 따라 생기지 않을 수 있으므로 실제 목록을 그대로 확인합니다.
    #expect(rawPaths.contains("문서.txt.prej"))
    #expect(rawPaths.contains { $0.hasPrefix("문서.txt.r") })
    #expect(rawPaths.count > 1)

    let visible = store.visibleStatuses.map { $0.path.precomposedStringWithCanonicalMapping }
    #expect(visible == ["문서.txt"])
    #expect(store.selectAllStatusPaths.isEmpty)
    #expect(store.selectableStatusPaths.isEmpty)
}

/// 내용 충돌과 속성 충돌을 한 파일에 함께 만들어 산출물 네 개를 남깁니다.
private final class ConflictArtifactFixture {
    let root: URL
    let workingCopy: URL
    let client: SVNClient
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
            .appendingPathComponent("conflict-artifact-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        let publisher = root.appendingPathComponent("publisher", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path])
        let repositoryURL = repository.absoluteString + "trunk"
        _ = try Self.run(svnPath, ["mkdir", repositoryURL, "-m", "trunk"])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, publisher.path])
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path])
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )

        try Data("기준\n".utf8).write(to: publisher.appendingPathComponent("문서.txt"))
        _ = try Self.run(svnPath, ["add", "문서.txt"], currentDirectory: publisher)
        _ = try Self.run(svnPath, ["propset", "x:flag", "기준", "문서.txt"], currentDirectory: publisher)
        _ = try Self.run(svnPath, ["commit", "-m", "기준"], currentDirectory: publisher)
        _ = try Self.run(svnPath, ["update"], currentDirectory: workingCopy)

        try Data("내 편집\n".utf8).write(to: workingCopy.appendingPathComponent("문서.txt"))
        _ = try Self.run(svnPath, ["propset", "x:flag", "내 값", "문서.txt"], currentDirectory: workingCopy)

        try Data("서버 편집\n".utf8).write(to: publisher.appendingPathComponent("문서.txt"))
        _ = try Self.run(svnPath, ["propset", "x:flag", "서버 값", "문서.txt"], currentDirectory: publisher)
        _ = try Self.run(svnPath, ["commit", "-m", "서버"], currentDirectory: publisher)
        _ = try Self.run(
            svnPath,
            ["update", "--accept", "postpone"],
            currentDirectory: workingCopy
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func makeStore() -> ProjectStore {
        let project = SVNProject(name: "충돌 산출물", path: workingCopy.path)
        return ProjectStore(
            client: client,
            credentialStore: ConflictArtifactCredentialStore(),
            persistence: ConflictArtifactPersistence(projects: [project]),
            projectAccessManager: ConflictArtifactAccessManager(),
            projectPathChecker: ConflictArtifactPathChecker(),
            volumeNormalizationProbe: ConflictArtifactVolumeProbe(),
            settingsDefaults: UserDefaults(suiteName: "conflict-artifact-\(UUID().uuidString)")!,
            updateBadgeRefreshInterval: nil
        )
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
            throw ConflictArtifactCommandError(
                command: ([executable] + arguments).joined(separator: " "),
                output: text
            )
        }
        return text
    }
}

private struct ConflictArtifactCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String
    var description: String { "\(command)\n\(output)" }
}

private struct ConflictArtifactCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct ConflictArtifactPersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private final class ConflictArtifactAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}

private struct ConflictArtifactPathChecker: ProjectPathChecking {
    func directoryExists(at _: String) -> Bool { true }
}

private actor ConflictArtifactVolumeProbe: VolumeNormalizationProbing {
    func preservesPrecomposedFilenames(at _: String) async -> Bool? { true }
}
