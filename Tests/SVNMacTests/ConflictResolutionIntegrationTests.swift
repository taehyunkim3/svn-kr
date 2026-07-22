import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func realSVNTextAndBinaryChoicesPreserveExactSelectedAndRecoveryBytes() async throws {
    let fixture = try RealSVNConflictFixture()
    defer { fixture.remove() }

    for conflict in fixture.contentConflicts {
        let requestedPath = conflict.choice == .working
            ? conflict.path.decomposedStringWithCanonicalMapping
            : conflict.path
        let snapshot = try await fixture.client.workingCopySnapshot(at: fixture.conflictedWorkingCopy.path)
        let resolvedPath = try #require(snapshot.resolvedPath(for: requestedPath))
        let versionedPath = conflict.choice == .working
            ? resolvedPath.precomposedStringWithCanonicalMapping
            : resolvedPath
        let details = try #require(try await fixture.client.conflictDetails(
            at: fixture.conflictedWorkingCopy.path,
            relativePath: versionedPath
        ))
        #expect(details.type == "text")
        #expect((details.myFile != nil) == !conflict.isBinary)
        #expect(details.serverFile != nil)

        let session = try fixture.service.prepareSession(
            details,
            projectID: fixture.projectID,
            workingCopyPath: fixture.conflictedWorkingCopy.path,
            requestedPath: requestedPath,
            versionedPath: versionedPath
        )
        #expect(session.wasCanonicallyResolved == (conflict.choice == .working))
        #expect(try Data(contentsOf: session.mine.url) == conflict.mineBytes)
        #expect(try Data(contentsOf: session.server.url) == conflict.serverBytes)

        let latestWorkingBytes = Data("selection-time-\(conflict.path)".utf8) + Data([0x00, 0xFF])
        let workingURL = fixture.conflictedWorkingCopy.appendingPathComponent(conflict.path)
        try latestWorkingBytes.write(to: workingURL)
        let recoveryURL = try fixture.service.prepareWorkingFileForResolve(
            for: session,
            choice: conflict.choice,
            workingCopyPath: fixture.conflictedWorkingCopy.path
        )

        _ = try await fixture.client.resolveConflict(
            at: fixture.conflictedWorkingCopy.path,
            relativePath: session.versionedPath,
            choice: conflict.choice
        )

        let selectedBytes: Data
        switch conflict.choice {
        case .mineFull: selectedBytes = conflict.mineBytes
        case .theirsFull: selectedBytes = conflict.serverBytes
        case .working: selectedBytes = latestWorkingBytes
        }
        #expect(try Data(contentsOf: workingURL) == selectedBytes)
        #expect(try Data(contentsOf: recoveryURL) == latestWorkingBytes)
    }

    let statuses = try await fixture.client.status(at: fixture.conflictedWorkingCopy.path)
    for conflict in fixture.contentConflicts {
        #expect(!statuses.contains { $0.path == conflict.path && $0.item == .conflicted })
    }
}

@Test func realSVNPropertyAndTreeConflictsRemainUnsupportedAndUnresolved() async throws {
    let fixture = try RealSVNConflictFixture()
    defer { fixture.remove() }

    let propertyDetails = try #require(try await fixture.client.conflictDetails(
        at: fixture.conflictedWorkingCopy.path,
        relativePath: fixture.propertyConflictPath
    ))
    let treeDetails = try #require(try await fixture.client.conflictDetails(
        at: fixture.conflictedWorkingCopy.path,
        relativePath: fixture.treeConflictPath
    ))
    #expect(propertyDetails.type == "property")
    #expect(treeDetails.type == "tree")

    for details in [propertyDetails, treeDetails] {
        let error = #expect(throws: ConflictFileError.self) {
            try fixture.service.prepareSession(
                details,
                projectID: fixture.projectID,
                workingCopyPath: fixture.conflictedWorkingCopy.path
            )
        }
        guard case let .unsupportedType(type) = error else {
            Issue.record("속성/트리 충돌은 지원하지 않는 유형으로 남아야 합니다.")
            continue
        }
        #expect(type == details.type)
    }

    let statusXML = try fixture.runSVN(["status", "--xml", fixture.conflictedWorkingCopy.path])
    #expect(statusXML.contains("props=\"conflicted\""))
    #expect(statusXML.contains("tree-conflicted=\"true\""))
    #expect(try await fixture.client.conflictDetails(
        at: fixture.conflictedWorkingCopy.path,
        relativePath: fixture.propertyConflictPath
    )?.type == "property")
    #expect(try await fixture.client.conflictDetails(
        at: fixture.conflictedWorkingCopy.path,
        relativePath: fixture.treeConflictPath
    )?.type == "tree")
}

private struct RealContentConflict {
    let path: String
    let mineBytes: Data
    let serverBytes: Data
    let choice: SVNConflictChoice
    let isBinary: Bool
}

private final class RealSVNConflictFixture {
    let root: URL
    let repository: URL
    let publishingWorkingCopyRoot: URL
    let publishingWorkingCopy: URL
    let conflictedWorkingCopyRoot: URL
    let conflictedWorkingCopy: URL
    let backupRoot: URL
    let projectID = UUID()
    let svnPath: String
    let svnadminPath: String
    let client: SVNClient
    let service: ConflictFileService
    let propertyConflictPath = "property.txt"
    let treeConflictPath = "tree.txt"
    let contentConflicts: [RealContentConflict] = [
        RealContentConflict(
            path: "text-mine.txt",
            mineBytes: Data("text local mine\n".utf8),
            serverBytes: Data("text server theirs\n".utf8),
            choice: .mineFull,
            isBinary: false
        ),
        RealContentConflict(
            path: "text-theirs.txt",
            mineBytes: Data("other text local mine\n".utf8),
            serverBytes: Data("other text server theirs\n".utf8),
            choice: .theirsFull,
            isBinary: false
        ),
        RealContentConflict(
            path: "binary-mine.bin",
            mineBytes: Data([0x4D, 0x49, 0x4E, 0x45, 0x00, 0xFF]),
            serverBytes: Data([0x53, 0x45, 0x52, 0x56, 0x00, 0xFE]),
            choice: .mineFull,
            isBinary: true
        ),
        RealContentConflict(
            path: "binary-theirs.bin",
            mineBytes: Data([0x4C, 0x4F, 0x43, 0x41, 0x4C, 0x00, 0xFD]),
            serverBytes: Data([0x52, 0x45, 0x4D, 0x4F, 0x54, 0x45, 0xFC]),
            choice: .theirsFull,
            isBinary: true
        ),
        RealContentConflict(
            path: "주간보고서.hwp",
            mineBytes: Data([0x48, 0x57, 0x50, 0x2D, 0x4D, 0x49, 0x4E, 0x45, 0x00, 0xFB]),
            serverBytes: Data([0x48, 0x57, 0x50, 0x2D, 0x53, 0x45, 0x52, 0x56, 0x00, 0xFA]),
            choice: .working,
            isBinary: true
        ),
    ]

    init() throws {
        let fileManager = FileManager.default
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
            .appendingPathComponent("svn-real-conflict-choice-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        publishingWorkingCopyRoot = root.appendingPathComponent("publisher", isDirectory: true)
        publishingWorkingCopy = publishingWorkingCopyRoot
            .appendingPathComponent("사업관리", isDirectory: true)
        conflictedWorkingCopyRoot = root.appendingPathComponent("conflicted", isDirectory: true)
        conflictedWorkingCopy = conflictedWorkingCopyRoot
            .appendingPathComponent("사업관리", isDirectory: true)
        backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        client = SVNClient(
            executablePath: svnPath,
            configDirectoryPath: root.appendingPathComponent("svn-config", isDirectory: true).path
        )
        service = ConflictFileService(backupRootURL: backupRoot)

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try Self.run(svnadminPath, ["create", repository.path])
        let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
        let trunkURL = repositoryURL + "trunk"
        _ = try Self.run(svnPath, ["mkdir", trunkURL, "-m", "create trunk"])
        _ = try Self.run(svnPath, ["checkout", trunkURL, publishingWorkingCopyRoot.path])
        try fileManager.createDirectory(at: publishingWorkingCopy, withIntermediateDirectories: false)

        for conflict in contentConflicts where conflict.choice != .working {
            let base = conflict.isBinary
                ? Data([0x42, 0x41, 0x53, 0x45, 0x00, UInt8(conflict.path.count)])
                : Data("base \(conflict.path)\n".utf8)
            try base.write(to: publishingWorkingCopy.appendingPathComponent(conflict.path))
        }
        try Data("property base\n".utf8).write(to: publishingWorkingCopy.appendingPathComponent(propertyConflictPath))
        try Data("tree base\n".utf8).write(to: publishingWorkingCopy.appendingPathComponent(treeConflictPath))
        _ = try Self.run(svnPath, ["add", publishingWorkingCopy.path])
        for conflict in contentConflicts where conflict.isBinary && conflict.choice != .working {
            _ = try Self.run(svnPath, [
                "propset", "svn:mime-type", "application/octet-stream",
                publishingWorkingCopy.appendingPathComponent(conflict.path).path,
            ])
        }
        _ = try Self.run(svnPath, [
            "propset", "integration:flag", "base",
            publishingWorkingCopy.appendingPathComponent(propertyConflictPath).path,
        ])
        _ = try Self.run(svnPath, ["commit", publishingWorkingCopyRoot.path, "-m", "initial files"])
        for conflict in contentConflicts where conflict.choice == .working {
            let importSource = root.appendingPathComponent("working-choice-base.bin")
            try Data([0x48, 0x57, 0x50, 0x2D, 0x42, 0x41, 0x53, 0x45, 0x00]).write(to: importSource)
            let encodedPath = try #require(
                conflict.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            )
            let encodedProjectPath = try #require(
                publishingWorkingCopy.lastPathComponent.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed
                )
            )
            _ = try Self.run(svnPath, [
                "import", importSource.path, "\(trunkURL)/\(encodedProjectPath)/\(encodedPath)",
                "-m", "import NFC conflict path",
            ])
        }
        _ = try Self.run(svnPath, ["update", publishingWorkingCopyRoot.path])
        _ = try Self.run(svnPath, ["checkout", trunkURL, conflictedWorkingCopyRoot.path])

        for conflict in contentConflicts {
            try conflict.serverBytes.write(to: publishingWorkingCopy.appendingPathComponent(conflict.path))
        }
        _ = try Self.run(svnPath, [
            "propset", "integration:flag", "server",
            publishingWorkingCopy.appendingPathComponent(propertyConflictPath).path,
        ])
        _ = try Self.run(svnPath, ["delete", publishingWorkingCopy.appendingPathComponent(treeConflictPath).path])
        _ = try Self.run(svnPath, ["commit", publishingWorkingCopyRoot.path, "-m", "server changes"])

        for conflict in contentConflicts {
            try conflict.mineBytes.write(to: conflictedWorkingCopy.appendingPathComponent(conflict.path))
        }
        _ = try Self.run(svnPath, [
            "propset", "integration:flag", "mine",
            conflictedWorkingCopy.appendingPathComponent(propertyConflictPath).path,
        ])
        try Data("tree local edit\n".utf8).write(to: conflictedWorkingCopy.appendingPathComponent(treeConflictPath))
        _ = try Self.run(svnPath, ["update", "--non-interactive", conflictedWorkingCopyRoot.path])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func runSVN(_ arguments: [String]) throws -> String {
        try Self.run(svnPath, arguments)
    }

    private static func firstExecutable(at paths: [String]) -> String? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    @discardableResult
    private static func run(
        _ executablePath: String,
        _ arguments: [String],
        at directory: URL? = nil
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw RealSVNConflictCommandError(
                command: ([executablePath] + arguments).joined(separator: " "),
                output: text
            )
        }
        return text
    }
}

private struct RealSVNConflictCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String

    var description: String { "Command failed: \(command)\n\(output)" }
}
