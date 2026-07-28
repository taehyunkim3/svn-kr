import Foundation

public enum SVNApplicationSupport {
    public static let currentDirectoryName = "SVN KR"
    public static let legacyDirectoryName = "SVN Mac"
    public static let keychainService = "com.mrdevello.svnmac.credentials"

    public static func rootDirectory(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try migrateRoot(in: applicationSupport, fileManager: fileManager)
    }

    public static func migrateRoot(
        in applicationSupport: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let current = applicationSupport.appendingPathComponent(
            currentDirectoryName,
            isDirectory: true
        )
        let legacy = applicationSupport.appendingPathComponent(
            legacyDirectoryName,
            isDirectory: true
        )
        if !fileManager.fileExists(atPath: current.path),
           fileManager.fileExists(atPath: legacy.path) {
            try fileManager.moveItem(at: legacy, to: current)
        }
        try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        return current
    }
}
