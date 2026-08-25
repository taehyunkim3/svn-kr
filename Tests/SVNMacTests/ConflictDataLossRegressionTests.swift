import Foundation
import SVNCore
import Testing
@testable import SVNMac

// 감사 A 1번·2번: 백업 없이 사용자 문서가 사라지던 두 경로의 회귀 테스트입니다.
// 두 테스트 모두 실제 `svn` 을 실행합니다. 재현 조건이 SVN 출력 형태에 달려 있어
// 가짜 클라이언트로는 같은 사고를 다시 잡아낼 수 없습니다.

// MARK: - 1번: 텍스트·속성 동시 충돌

@MainActor
@Test func combinedTextAndPropertyConflictKeepsContentConflictProtection() async throws {
    let fixture = try CombinedConflictFixture()
    defer { fixture.remove() }

    // `svn info --xml` 은 충돌마다 `<conflict>` 요소를 내보내고 파서는 마지막 요소만 남깁니다.
    // 그래서 내용 충돌이 있는데도 분류가 "property" 로 도착합니다. 이 사실이 사고의 출발점입니다.
    // 디스크가 한글 이름을 자모 분리로 저장할 수 있으므로 앱과 같은 방식으로 경로를 맞춥니다.
    let snapshot = try await fixture.client.workingCopySnapshot(at: fixture.workingCopy.path)
    let versionedPath = try #require(snapshot.resolvedPath(for: fixture.conflictPath))
    let details = try #require(try await fixture.client.conflictDetails(
        at: fixture.workingCopy.path,
        relativePath: versionedPath
    ))
    #expect(details.type == "property")

    let pathIdentity = SVNPathIdentity(rawPath: versionedPath)
    let entry = try #require(snapshot.statuses.first {
        SVNPathIdentity(rawPath: $0.path) == pathIdentity
    })
    #expect(entry.item == .conflicted)
    #expect(entry.propertyState == .conflicted)

    let store = fixture.makeStore()
    await store.prepareConflictResolution(for: fixture.conflictPath)

    // 내용 충돌이 함께 있으면 반드시 내용 충돌 화면으로 가야 합니다.
    // 속성 화면으로 가면 백업 없이 작업 파일이 서버 버전으로 덮어써집니다.
    let session = try #require(store.activeConflictSession)
    #expect(store.recoveryState.propertyConflictSession == nil)
    #expect(store.activeTreeConflictSession == nil)
    #expect(session.hasPropertyConflict)
    #expect(session.propertyNames == ["integration:flag"])
    #expect(try Data(contentsOf: session.server.url) == fixture.serverBytes)

    // 사용자가 화면을 열어 둔 사이 손으로 더 편집한 내용까지 복구본에 남아야 합니다.
    let latestWorkingBytes = Data("사용자가 마지막으로 손댄 내용\n".utf8)
    let workingURL = fixture.workingCopy.appendingPathComponent(versionedPath)
    try latestWorkingBytes.write(to: workingURL)
    let sessionDirectory = session.directoryURL

    await store.resolveActiveConflict(using: .theirsFull)

    #expect(store.errorMessage == nil)
    #expect(store.activeConflictSession == nil)
    #expect(try Data(contentsOf: workingURL) == fixture.serverBytes)

    let propertyValue = try fixture.runSVN([
        "propget", "integration:flag", workingURL.path,
    ]).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(propertyValue == "server")

    let recovered = try regularFileContents(under: sessionDirectory)
    #expect(recovered.contains(latestWorkingBytes))
    #expect(recovered.contains(fixture.serverBytes))
}

// MARK: - 2번: 디렉터리 트리 충돌의 서버 복구

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

@Test func classifyRoutesCombinedConflictToContentPathAndKeepsPureCases() {
    let propertyTyped = SVNConflictDetails(
        path: "예산.xlsx",
        type: "property",
        operation: "update",
        myFile: "예산.xlsx.mine",
        serverFile: "예산.xlsx.r2"
    )
    #expect(
        ConflictClassification.classify(
            details: propertyTyped,
            statusItem: .conflicted,
            propertyState: .conflicted
        ) == .text(hasPropertyConflict: true)
    )
    #expect(
        ConflictClassification.classify(
            details: propertyTyped,
            statusItem: .modified,
            propertyState: .conflicted
        ) == .property
    )
    #expect(
        ConflictClassification.classify(
            details: SVNConflictDetails(path: "문서", type: "tree", operation: "update"),
            statusItem: .added,
            propertyState: .none
        ) == .tree
    )
    #expect(
        ConflictClassification.classify(
            details: SVNConflictDetails(
                path: "보고서.txt",
                type: "text",
                operation: "update",
                myFile: "보고서.txt.mine",
                serverFile: "보고서.txt.r2"
            ),
            statusItem: .conflicted,
            propertyState: .none
        ) == .text(hasPropertyConflict: false)
    )
    #expect(
        ConflictClassification.classify(
            details: SVNConflictDetails(path: "알수없음", type: "unknown", operation: "update"),
            statusItem: .modified,
            propertyState: .none
        ) == .unsupported("unknown")
    )

    let normalized = ConflictClassification.textConflictDetails(from: propertyTyped)
    #expect(normalized.type == "text")
    #expect(normalized.myFile == propertyTyped.myFile)
    #expect(normalized.serverFile == propertyTyped.serverFile)
}

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

/// 한 파일에 내용 충돌과 속성 충돌을 동시에 만듭니다.
/// 두 사람이 같은 문서를 편집하면서 같은 속성을 서로 다르게 바꾸면 실제로 이 상태가 됩니다.
private final class CombinedConflictFixture: DataLossFixture {
    let conflictPath = "예산.xlsx"
    let serverBytes = Data("서버가 커밋한 내용\n".utf8)
    let mineBytes = Data("내가 작업하던 내용\n".utf8)

    init() throws {
        try super.init(name: "combined")
        _ = try runSVN(["checkout", repositoryURL, publisher.path])
        try Data("처음 내용\n".utf8).write(to: publisher.appendingPathComponent(conflictPath))
        _ = try runSVN(["add", publisher.appendingPathComponent(conflictPath).path])
        _ = try runSVN([
            "propset", "integration:flag", "base",
            publisher.appendingPathComponent(conflictPath).path,
        ])
        _ = try runSVN(["commit", publisher.path, "-m", "initial"])
        _ = try runSVN(["checkout", repositoryURL, workingCopy.path])

        try serverBytes.write(to: publisher.appendingPathComponent(conflictPath))
        _ = try runSVN([
            "propset", "integration:flag", "server",
            publisher.appendingPathComponent(conflictPath).path,
        ])
        _ = try runSVN(["commit", publisher.path, "-m", "server change"])

        try mineBytes.write(to: workingCopy.appendingPathComponent(conflictPath))
        _ = try runSVN([
            "propset", "integration:flag", "mine",
            workingCopy.appendingPathComponent(conflictPath).path,
        ])
        _ = try runSVN(["update", "--non-interactive", "--accept", "postpone", workingCopy.path])
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
