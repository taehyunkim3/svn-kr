import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test func realSVNTextAndBinaryChoicesPreserveExactSelectedAndRecoveryBytes() async throws {
    let fixture = try RealSVNConflictFixture()
    defer { fixture.remove() }

    for conflict in fixture.contentConflicts {
        let details = try #require(try await fixture.client.conflictDetails(
            at: fixture.conflictedWorkingCopy.path,
            relativePath: conflict.path
        ))
        #expect(details.type == "text")
        #expect((details.myFile != nil) == !conflict.isBinary)
        #expect(details.serverFile != nil)

        let session = try fixture.service.prepareSession(
            details,
            projectID: fixture.projectID,
            workingCopyPath: fixture.conflictedWorkingCopy.path
        )
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
            relativePath: conflict.path,
            choice: conflict.choice
        )

        let selectedBytes: Data
        switch conflict.choice {
        case .mineFull: selectedBytes = conflict.mineBytes
        case .theirsFull: selectedBytes = conflict.serverBytes
        case .working: selectedBytes = Data()
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
    let publishingWorkingCopy: URL
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
        publishingWorkingCopy = root.appendingPathComponent("publisher", isDirectory: true)
        conflictedWorkingCopy = root.appendingPathComponent("conflicted", isDirectory: true)
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
        _ = try Self.run(svnPath, ["checkout", trunkURL, publishingWorkingCopy.path])

        for conflict in contentConflicts {
            let base = conflict.isBinary
                ? Data([0x42, 0x41, 0x53, 0x45, 0x00, UInt8(conflict.path.count)])
                : Data("base \(conflict.path)\n".utf8)
            try base.write(to: publishingWorkingCopy.appendingPathComponent(conflict.path))
        }
        try Data("property base\n".utf8).write(to: publishingWorkingCopy.appendingPathComponent(propertyConflictPath))
        try Data("tree base\n".utf8).write(to: publishingWorkingCopy.appendingPathComponent(treeConflictPath))
        let initialPaths = contentConflicts.map { publishingWorkingCopy.appendingPathComponent($0.path).path }
            + [
                publishingWorkingCopy.appendingPathComponent(propertyConflictPath).path,
                publishingWorkingCopy.appendingPathComponent(treeConflictPath).path,
            ]
        _ = try Self.run(svnPath, ["add"] + initialPaths)
        for conflict in contentConflicts where conflict.isBinary {
            _ = try Self.run(svnPath, [
                "propset", "svn:mime-type", "application/octet-stream",
                publishingWorkingCopy.appendingPathComponent(conflict.path).path,
            ])
        }
        _ = try Self.run(svnPath, [
            "propset", "integration:flag", "base",
            publishingWorkingCopy.appendingPathComponent(propertyConflictPath).path,
        ])
        _ = try Self.run(svnPath, ["commit", publishingWorkingCopy.path, "-m", "initial files"])
        _ = try Self.run(svnPath, ["checkout", trunkURL, conflictedWorkingCopy.path])

        for conflict in contentConflicts {
            try conflict.serverBytes.write(to: publishingWorkingCopy.appendingPathComponent(conflict.path))
        }
        _ = try Self.run(svnPath, [
            "propset", "integration:flag", "server",
            publishingWorkingCopy.appendingPathComponent(propertyConflictPath).path,
        ])
        _ = try Self.run(svnPath, ["delete", publishingWorkingCopy.appendingPathComponent(treeConflictPath).path])
        _ = try Self.run(svnPath, ["commit", publishingWorkingCopy.path, "-m", "server changes"])

        for conflict in contentConflicts {
            try conflict.mineBytes.write(to: conflictedWorkingCopy.appendingPathComponent(conflict.path))
        }
        _ = try Self.run(svnPath, [
            "propset", "integration:flag", "mine",
            conflictedWorkingCopy.appendingPathComponent(propertyConflictPath).path,
        ])
        try Data("tree local edit\n".utf8).write(to: conflictedWorkingCopy.appendingPathComponent(treeConflictPath))
        _ = try Self.run(svnPath, ["update", "--non-interactive", conflictedWorkingCopy.path])
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
    private static func run(_ executablePath: String, _ arguments: [String]) throws -> String {
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
