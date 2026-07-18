import Foundation
import Testing

@Test func appUsesBorderedButtonsByDefault() throws {
    let sources = try svnMacSourceFiles()
    let appSource = try String(contentsOf: sources.appendingPathComponent("SVNMacApp.swift"), encoding: .utf8)

    #expect(appSource.contains(".buttonStyle(.bordered)"))
}

@Test func appViewsDoNotHideActionsWithBorderlessButtons() throws {
    let sources = try svnMacSourceFiles()
    let files = try FileManager.default.contentsOfDirectory(
        at: sources,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }

    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(!source.contains(".buttonStyle(.borderless)"), "Borderless action in \(file.lastPathComponent)")
    }
}

private func svnMacSourceFiles() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
