import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func versionedFileActionValidationRejectsExistingDestinationAndUnversionedSource() throws {
    let existingDestination = #expect(throws: VersionedFileActionError.self) {
        try VersionedFileActionValidation.destinationRelativePath(
            sourceRelativePath: "문서/보고서.hwp",
            destinationName: "보고서_최종.hwp",
            sourceIsVersioned: true,
            destinationExists: true
        )
    }
    #expect(existingDestination == .destinationExists("문서/보고서_최종.hwp"))

    let unversionedSource = #expect(throws: VersionedFileActionError.self) {
        try VersionedFileActionValidation.destinationRelativePath(
            sourceRelativePath: "문서/새 보고서.hwp",
            destinationName: "새 보고서_최종.hwp",
            sourceIsVersioned: false,
            destinationExists: false
        )
    }
    #expect(unversionedSource == .sourceIsNotVersioned("문서/새 보고서.hwp"))
}

@MainActor
@Test func repositoryConnectionFailureCreatesRelocationRequestWithOriginalError() async throws {
    let fixture = try RepositoryMaintenanceFixture()
    defer { fixture.remove() }
    let store = fixture.makeStore()
    let message = "svn: E170013: Unable to connect to a repository at URL"
    store.errorMessage = message

    let offered = await store.captureRepositoryConnectionError(message)

    #expect(offered)
    #expect(store.errorMessage == nil)
    #expect(store.isShowingCredentials)
    #expect(store.recoveryState.repositoryRelocationRequest?.currentURL == fixture.repositoryURL)
    #expect(store.recoveryState.repositoryRelocationRequest?.connectionErrorMessage == message)
}

@MainActor
@Test func realSVNRepositoryMaintenancePreservesHistoryChangesAndNeedsLock() async throws {
    let fixture = try RepositoryMaintenanceFixture()
    defer { fixture.remove() }
    try fixture.write("초안", relativePath: "report.hwp")
    try fixture.write("원본", relativePath: "공유.xlsx")
    try fixture.addAndCommit(message: "원본 문서")
    try fixture.write("미커밋 변경", relativePath: "공유.xlsx")
    let store = fixture.makeStore()

    let movedRepository = fixture.root.appendingPathComponent("repository-moved", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.repository, to: movedRepository)
    let connectionError = try #require(await #expect(throws: (any Error).self) {
        _ = try await fixture.client.update(at: fixture.workingCopy.path)
    })
    #expect(SVNClient.isRepositoryConnectionError(connectionError))

    await store.requestRepositoryRelocation()
    #expect(store.isShowingCredentials)
    let relocatedURL = movedRepository.absoluteString + "trunk"
    #expect(await store.relocateSelectedRepository(to: relocatedURL))
    _ = try await fixture.client.update(at: fixture.workingCopy.path)
    #expect(try fixture.read(relativePath: "공유.xlsx") == "미커밋 변경")
    #expect(try fixture.runSVN(["status"]).contains("M       공유.xlsx"))

    store.requestVersionedFileAction(.move, path: "report.hwp")
    let moveRequest = try #require(store.recoveryState.versionedFileActionRequest)
    #expect(await store.performVersionedFileAction(moveRequest, destinationName: "report-final.hwp"))
    store.requestVersionedFileAction(.copy, path: "report-final.hwp")
    let copyRequest = try #require(store.recoveryState.versionedFileActionRequest)
    #expect(await store.performVersionedFileAction(copyRequest, destinationName: "report-release.hwp"))
    try fixture.commit(message: "이력 보존 이름 변경과 복사")

    let committedEntries = try await fixture.client.workingCopyEntries(at: fixture.workingCopy.path)
    let committedMovedPath = "report-final.hwp"
    let committedCopyPath = "report-release.hwp"
    let sharedPath = try #require(committedEntries.first {
        $0.path.precomposedStringWithCanonicalMapping == "공유.xlsx"
    }?.path)
    let moveLog = try fixture.runSVN(["log", "--verbose", committedMovedPath])
    let copyLog = try fixture.runSVN(["log", "--verbose", committedCopyPath])
    #expect(moveLog.contains("원본 문서"))
    #expect(copyLog.contains("원본 문서"))
    #expect(moveLog.contains("from /trunk/report.hwp:2"))

    #expect(await store.setNeedsLock(true, paths: [sharedPath, committedMovedPath]))
    let lockedProperties = try await fixture.client.properties(
        at: fixture.workingCopy.path,
        relativePath: sharedPath
    )
    #expect(lockedProperties.contains { $0.name == "svn:needs-lock" })
    await store.loadNeedsLockState(for: [sharedPath, committedMovedPath])
    #expect(store.recoveryState.needsLockPaths == [sharedPath, committedMovedPath])

    #expect(await store.setNeedsLock(false, paths: [sharedPath, committedMovedPath]))
    let unlockedProperties = try await fixture.client.properties(
        at: fixture.workingCopy.path,
        relativePath: sharedPath
    )
    #expect(!unlockedProperties.contains { $0.name == "svn:needs-lock" })
}

@MainActor
@Test func filePropertiesRequestReloadsNeedsLockFromSVN() async throws {
    let fixture = try RepositoryMaintenanceFixture()
    defer { fixture.remove() }
    try fixture.write("원본", relativePath: "report.hwp")
    try fixture.addAndCommit(message: "원본 문서")
    _ = try await fixture.client.setProperty(
        named: "svn:needs-lock",
        value: Data("*".utf8),
        at: fixture.workingCopy.path,
        relativePath: "report.hwp"
    )
    let store = fixture.makeStore()

    store.requestFilePropertiesEdit(path: "report.hwp")
    let request = try #require(store.recoveryState.filePropertiesEditRequest)

    #expect(await store.loadNeedsLockState(for: request) == true)
    #expect(store.recoveryState.needsLockPaths == ["report.hwp"])

    #expect(await store.saveFileProperties(request, needsLock: false))
    #expect(store.recoveryState.filePropertiesEditRequest == nil)
    let propertiesAfterRemoval = try await fixture.client.properties(
        at: fixture.workingCopy.path,
        relativePath: "report.hwp"
    )
    #expect(!propertiesAfterRemoval.contains { $0.name == "svn:needs-lock" })

    store.requestFilePropertiesEdit(path: "report.hwp")
    let secondRequest = try #require(store.recoveryState.filePropertiesEditRequest)
    #expect(await store.loadNeedsLockState(for: secondRequest) == false)
    #expect(await store.saveFileProperties(secondRequest, needsLock: true))
    let propertiesAfterSetting = try await fixture.client.properties(
        at: fixture.workingCopy.path,
        relativePath: "report.hwp"
    )
    #expect(propertiesAfterSetting.contains { $0.name == "svn:needs-lock" })
}

@Test func repositoryRelocationEntryBelongsToFolderSettingsNotChangesOrAddSheet() throws {
    let sources = try repositoryMaintenanceSources()
    let changes = try String(
        contentsOf: sources.appendingPathComponent("ChangesView.swift"),
        encoding: .utf8
    )
    let dialogs = try String(
        contentsOf: sources.appendingPathComponent("RepositoryDialogs.swift"),
        encoding: .utf8
    )
    let addView = try viewSlice(
        dialogs,
        from: "struct AddRepositoryView: View",
        to: "struct CredentialsView: View"
    )
    let credentials = try viewSlice(
        dialogs,
        from: "struct CredentialsView: View",
        to: "struct RepositoryRelocationView: View"
    )

    #expect(changes.contains("if let repositoryURL = store.recoveryState.repositoryURL"))
    #expect(changes.contains("Text(repositoryURL)"))
    #expect(changes.contains("captureRepositoryConnectionError"))
    #expect(!changes.contains("requestRepositoryRelocation"))
    #expect(!changes.contains(".ui.repository.changeRepositoryLocation"))

    #expect(!addView.contains("requestRepositoryRelocation"))
    #expect(!addView.contains(".ui.repository.changeRepositoryLocation"))
    #expect(!addView.contains(".ui.repository.currentRepositoryUrl"))

    #expect(credentials.contains("requestRepositoryRelocation"))
    #expect(credentials.contains(".ui.repository.changeRepositoryLocation"))
    #expect(credentials.contains(".ui.repository.currentRepositoryUrl"))
    #expect(credentials.contains("repositoryRelocationRequest"))

    let urlLabel = try #require(credentials.range(of: ".ui.repository.currentRepositoryUrl"))
    let credentialFields = try #require(credentials.range(of: "CredentialFieldsGrid("))
    #expect(urlLabel.lowerBound < credentialFields.lowerBound)
    #expect(
        credentials.range(of: "Divider()", range: urlLabel.upperBound..<credentialFields.lowerBound) != nil
    )
}

@Test func repositoryMaintenanceViewsExposeActionsAndLocalizedStrings() throws {
    let sources = try repositoryMaintenanceSources()
    let changes = try String(
        contentsOf: sources.appendingPathComponent("ChangesView.swift"),
        encoding: .utf8
    )
    let browser = try String(
        contentsOf: sources.appendingPathComponent("WorkingCopyBrowserView.swift"),
        encoding: .utf8
    )
    let splitBrowser = try String(
        contentsOf: sources.appendingPathComponent("WorkingCopySplitBrowserView.swift"),
        encoding: .utf8
    )
    let content = try String(
        contentsOf: sources.appendingPathComponent("ContentView.swift"),
        encoding: .utf8
    )
    let dialogs = try String(
        contentsOf: sources.appendingPathComponent("RepositoryDialogs.swift"),
        encoding: .utf8
    )

    #expect(changes.contains("requestVersionedFileAction(.move"))
    #expect(changes.contains("setNeedsLock(true"))
    #expect(browser.contains("requestVersionedFileAction(.copy"))
    for source in [changes, browser, splitBrowser] {
        #expect(source.contains("requestFilePropertiesEdit"))
        #expect(source.contains(".ui.repository.editFileProperties"))
    }
    #expect(content.contains("FilePropertiesEditView"))
    #expect(content.contains("filePropertiesEditRequest"))
    #expect(dialogs.contains("RepositoryRelocationView"))
    #expect(dialogs.contains("repositoryRelocationRequest"))

    let keys = RepositoryMaintenanceLocalization.requiredKeys
    let resources = sources.appendingPathComponent("Resources", isDirectory: true)
    for relativePath in [
        "Localizable.xcstrings",
        "ko.lproj/Localizable.strings",
        "en.lproj/Localizable.strings",
    ] {
        let contents = try String(
            contentsOf: resources.appendingPathComponent(relativePath),
            encoding: .utf8
        )
        for key in keys {
            #expect(
                contents.contains(key.rawValue),
                "\(key.rawValue) is missing from \(relativePath)"
            )
        }
    }
}

private func repositoryMaintenanceSources() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}

private func viewSlice(_ source: String, from start: String, to end: String) throws -> String {
    let startRange = try #require(source.range(of: start))
    let endRange = try #require(source.range(of: end))
    #expect(startRange.lowerBound < endRange.lowerBound)
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

private final class RepositoryMaintenanceFixture {
    let root: URL
    let repository: URL
    let workingCopy: URL
    let client: SVNClient
    let repositoryURL: String
    private let svnPath: String

    init() throws {
        svnPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
        ]))
        let svnadminPath = try #require(Self.firstExecutable(at: [
            "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
        ]))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-maintenance-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        workingCopy = root.appendingPathComponent("working-copy", isDirectory: true)
        let importDirectory = root.appendingPathComponent("import", isDirectory: true)
        let trunk = importDirectory.appendingPathComponent("trunk", isDirectory: true)
        try FileManager.default.createDirectory(at: trunk, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path], at: root)
        _ = try Self.run(
            svnPath,
            ["import", importDirectory.path, repository.absoluteString, "-m", "저장소 생성"],
            at: root
        )
        repositoryURL = repository.absoluteString + "trunk"
        _ = try Self.run(svnPath, ["checkout", repositoryURL, workingCopy.path], at: root)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
    }

    @MainActor
    func makeStore() -> ProjectStore {
        let project = SVNProject(name: "문서 공유", path: workingCopy.path)
        return ProjectStore(
            client: client,
            credentialStore: RepositoryMaintenanceCredentialStore(),
            persistence: RepositoryMaintenancePersistence(projects: [project]),
            projectAccessManager: RepositoryMaintenanceAccessManager(),
            updateBadgeRefreshInterval: nil
        )
    }

    func write(_ contents: String, relativePath: String) throws {
        try Data(contents.utf8).write(to: workingCopy.appendingPathComponent(relativePath))
    }

    func read(relativePath: String) throws -> String {
        try String(contentsOf: workingCopy.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func addAndCommit(message: String) throws {
        _ = try runSVN(["add", "--force", "."])
        try commit(message: message)
    }

    func commit(message: String) throws {
        _ = try runSVN(["commit", "-m", message])
    }

    func runSVN(_ arguments: [String]) throws -> String {
        try Self.run(svnPath, arguments, at: workingCopy)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "RepositoryMaintenanceFixture",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return output
    }
}

private struct RepositoryMaintenanceCredentialStore: CredentialStoring {
    func password(for _: UUID) throws -> String? { nil }
    func setPassword(_: String, for _: UUID) throws {}
    func deletePassword(for _: UUID) throws {}
}

private struct RepositoryMaintenancePersistence: ProjectPersisting {
    let projects: [SVNProject]
    func loadProjects() -> [SVNProject] { projects }
    func saveProjects(_: [SVNProject]) {}
}

private final class RepositoryMaintenanceAccessManager: ProjectAccessManaging {
    func makeBookmark(for _: URL) throws -> Data { Data() }
    func restoreAccess(for _: inout [SVNProject]) {}
    func beginAccessing(_: URL, for _: SVNProject.ID) {}
    func endAccessing(projectID _: SVNProject.ID) {}
    func endAccessing(url _: URL) {}
}
