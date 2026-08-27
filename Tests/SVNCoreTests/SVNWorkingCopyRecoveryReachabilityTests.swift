import Foundation
import Testing
@testable import SVNCore

@Test func realSVNNormalTreeConflictIsVisibleAndBlocksRecovery() async throws {
    let fileManager = FileManager.default
    let svnPath = try #require(reachabilityExecutable(at: [
        "/opt/homebrew/bin/svn", "/usr/local/bin/svn", "/usr/bin/svn",
    ]))
    let svnadminPath = try #require(reachabilityExecutable(at: [
        "/opt/homebrew/bin/svnadmin", "/usr/local/bin/svnadmin", "/usr/bin/svnadmin",
    ]))
    let hdiutilPath = "/usr/bin/hdiutil"
    #expect(fileManager.isExecutableFile(atPath: hdiutilPath))

    let fixture = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("svn-recovery-reachability-\(UUID().uuidString)", isDirectory: true)
    let image = fixture.appendingPathComponent("case-sensitive.dmg")
    let mount = fixture.appendingPathComponent("case-sensitive", isDirectory: true)
    let repository = fixture.appendingPathComponent("repository", isDirectory: true)
    let caseSensitiveWorkingCopy = mount.appendingPathComponent("wc", isDirectory: true)
    let normalWorkingCopy = fixture.appendingPathComponent("normal-wc", isDirectory: true)
    var mounted = false

    try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
    defer {
        if mounted {
            _ = try? runReachabilityCommand(hdiutilPath, ["detach", mount.path])
        }
        try? fileManager.removeItem(at: fixture)
    }

    _ = try runReachabilityCommand(hdiutilPath, [
        "create", "-size", "32m", "-fs", "Case-sensitive APFS",
        "-volname", "SVNRecoveryReachability", "-ov", image.path,
    ])
    _ = try runReachabilityCommand(hdiutilPath, [
        "attach", "-nobrowse", "-mountpoint", mount.path, image.path,
    ])
    mounted = true

    _ = try runReachabilityCommand(svnadminPath, ["create", repository.path])
    let repositoryURL = URL(fileURLWithPath: repository.path, isDirectory: true).absoluteString
    let trunkURL = repositoryURL + "trunk"
    let branchURL = repositoryURL + "branch"
    let composedRoot = "관리 폴더"
    let decomposedRoot = composedRoot.decomposedStringWithCanonicalMapping
    let conflictPath = "\(composedRoot)/충돌 폴더"
    let trackedPath = "\(conflictPath)/기존.txt"
    let repositorySetupScript = fixture.appendingPathComponent("create-repository-state.zsh")
    try Data("""
    #!/bin/zsh
    set -euo pipefail
    "\(svnPath)" mkdir --parents "\(trunkURL)/\(conflictPath)" -m 'base directories' >/dev/null
    "\(svnPath)" checkout "\(trunkURL)" "\(caseSensitiveWorkingCopy.path)" >/dev/null
    printf 'base' > "\(caseSensitiveWorkingCopy.path)/\(trackedPath)"
    "\(svnPath)" add "\(caseSensitiveWorkingCopy.path)/\(trackedPath)" >/dev/null
    "\(svnPath)" commit "\(caseSensitiveWorkingCopy.path)" -m base >/dev/null
    "\(svnPath)" update "\(caseSensitiveWorkingCopy.path)" >/dev/null
    "\(svnPath)" copy "\(trunkURL)" "\(branchURL)" -m branch >/dev/null
    """.utf8).write(to: repositorySetupScript)
    _ = try runReachabilityCommand("/bin/zsh", [repositorySetupScript.path])

    let conflictSetupScript = fixture.appendingPathComponent("create-tree-conflict-input.zsh")
    try Data("""
    #!/bin/zsh
    set -euo pipefail
    printf 'local-change' > "\(caseSensitiveWorkingCopy.path)/\(trackedPath)"
    "\(svnPath)" delete "\(branchURL)/\(conflictPath)" -m 'incoming delete' >/dev/null
    """.utf8).write(to: conflictSetupScript)
    _ = try runReachabilityCommand("/bin/zsh", [conflictSetupScript.path])
    let revision = try runReachabilityCommand(svnPath, [
        "info", "--show-item", "revision", repositoryURL,
    ]).trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try runReachabilityCommand(svnPath, [
        "merge", "-c", revision, branchURL, caseSensitiveWorkingCopy.path,
    ])

    let rawAliasRoot = caseSensitiveWorkingCopy.path + "/" + decomposedRoot
    let aliasSetupScript = fixture.appendingPathComponent("add-raw-alias.zsh")
    try Data("""
    #!/bin/zsh
    set -euo pipefail
    mkdir -p "\(rawAliasRoot)"
    printf 'scheduled' > "\(rawAliasRoot)/scheduled.bin"
    "\(svnPath)" add "\(rawAliasRoot)" >/dev/null
    """.utf8).write(to: aliasSetupScript)
    _ = try runReachabilityCommand("/bin/zsh", [aliasSetupScript.path])

    try fileManager.createDirectory(at: normalWorkingCopy, withIntermediateDirectories: true)
    try fileManager.copyItem(
        at: caseSensitiveWorkingCopy.appendingPathComponent(".svn", isDirectory: true),
        to: normalWorkingCopy.appendingPathComponent(".svn", isDirectory: true)
    )
    let physicalStateScript = fixture.appendingPathComponent("create-physical-state.zsh")
    try Data("""
    #!/bin/zsh
    set -euo pipefail
    mkdir -p "\(normalWorkingCopy.path)/\(conflictPath)"
    printf 'local-change' > "\(normalWorkingCopy.path)/\(trackedPath)"
    """.utf8).write(to: physicalStateScript)
    _ = try runReachabilityCommand("/bin/zsh", [physicalStateScript.path])
    _ = try runReachabilityCommand(hdiutilPath, ["detach", mount.path])
    mounted = false
    _ = try runReachabilityCommand(svnPath, [
        "revert", "--depth", "empty", normalWorkingCopy.path,
    ])

    let statusXML = try runReachabilityCommand(
        svnPath,
        ["status", "--verbose", "--no-ignore", "--xml"],
        at: normalWorkingCopy
    )
    let entries = try SVNXMLParser.workingCopyEntries(from: Data(statusXML.utf8))
    let conflictPathBytes = Data(conflictPath.utf8)
    let treeConflict = try #require(entries.first {
        $0.treeConflicted && Data($0.path.utf8) == conflictPathBytes
    })
    #expect(treeConflict.status == "normal")
    #expect(treeConflict.treeConflicted)
    #expect(treeConflict.propertyState == .none)
    #expect(!treeConflict.isSwitched)

    let client = SVNClient(
        executablePath: svnPath,
        configDirectoryPath: fixture.appendingPathComponent("svn-config", isDirectory: true).path
    )
    let snapshot = try await client.workingCopySnapshot(at: normalWorkingCopy.path)
    let canRepairCanonicalAliases = !snapshot.collisions.isEmpty
        && snapshot.collisions.allSatisfy { $0.repairableRawPath != nil }
    let preview = try await client.recoveryPreview(at: normalWorkingCopy.path)

    #expect(!canRepairCanonicalAliases)
    #expect(snapshot.collisions.count == 1)
    #expect(snapshot.collisions[0].canonicalPath == composedRoot)
    #expect(snapshot.collisions[0].repairableRawPath == nil)
    #expect(snapshot.statuses.contains {
        $0.item == .conflicted && Data($0.path.utf8) == conflictPathBytes
    })
    #expect(preview.blockingPaths == [conflictPath])
    #expect(preview.mappings.contains { $0.destinationPath == trackedPath && $0.status == .modified })
}

private func reachabilityExecutable(at paths: [String]) -> String? {
    paths.first(where: FileManager.default.isExecutableFile(atPath:))
}

@discardableResult
private func runReachabilityCommand(
    _ executablePath: String,
    _ arguments: [String],
    at workingDirectory: URL? = nil
) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw ReachabilityCommandError(
            command: ([executablePath] + arguments).joined(separator: " "),
            output: text
        )
    }
    return text
}

private struct ReachabilityCommandError: Error, CustomStringConvertible {
    let command: String
    let output: String

    var description: String { "Command failed: \(command)\n\(output)" }
}
