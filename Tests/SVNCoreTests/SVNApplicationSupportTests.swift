import Foundation
import Testing
@testable import SVNCore

@Test func migratesLegacyApplicationSupportDirectoryWithoutDataLoss() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-support-migration-test-\(UUID().uuidString)", isDirectory: true)
    let legacy = base.appendingPathComponent(SVNApplicationSupport.legacyDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let marker = legacy.appendingPathComponent("existing-config")
    try Data("preserved".utf8).write(to: marker)
    defer { try? FileManager.default.removeItem(at: base) }

    let migrated = try SVNApplicationSupport.migrateRoot(in: base)

    #expect(migrated.lastPathComponent == SVNApplicationSupport.currentDirectoryName)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(try Data(contentsOf: migrated.appendingPathComponent("existing-config")) == Data("preserved".utf8))
}

@Test func existingCurrentApplicationSupportDirectoryWinsOverLegacy() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-support-current-test-\(UUID().uuidString)", isDirectory: true)
    let current = base.appendingPathComponent(SVNApplicationSupport.currentDirectoryName, isDirectory: true)
    let legacy = base.appendingPathComponent(SVNApplicationSupport.legacyDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let result = try SVNApplicationSupport.migrateRoot(in: base)

    #expect(result == current)
    #expect(FileManager.default.fileExists(atPath: legacy.path))
}
