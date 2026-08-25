import Foundation
import SVNCore

enum RevisionFileError: LocalizedError {
    case historyClientUnavailable
    case missingWorkingFile
    case unsafeWorkingFile
    case pathOutsideWorkingCopy
    case backupRootInsideWorkingCopy
    case backupVerificationFailed
    case replacementVerificationFailed
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .historyClientUnavailable:
            AppLanguage.current.localized(.ui.revision.historyClientUnavailable)
        case .missingWorkingFile:
            AppLanguage.current.localized(.ui.revision.restoreMissingWorkingFile)
        case .unsafeWorkingFile:
            AppLanguage.current.localized(.ui.revision.restoreUnsafeWorkingFile)
        case .pathOutsideWorkingCopy:
            AppLanguage.current.localized(.ui.revision.restorePathOutsideWorkingCopy)
        case .backupRootInsideWorkingCopy:
            AppLanguage.current.localized(.ui.revision.restoreBackupInsideWorkingCopy)
        case .backupVerificationFailed:
            AppLanguage.current.localized(.ui.revision.restoreBackupVerificationFailed)
        case .replacementVerificationFailed:
            AppLanguage.current.localized(.ui.revision.restoreReplacementVerificationFailed)
        case .invalidDestination:
            AppLanguage.current.localized(.ui.revision.saveInvalidDestination)
        }
    }
}

struct RevisionRestoreResult: Equatable {
    let recoveryURL: URL
}

actor RevisionFileService {
    private let fileManager: FileManager
    private let backupRootURL: URL?
    private let replaceItem: (URL, URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        backupRootURL: URL? = nil,
        replaceItem: ((URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.backupRootURL = backupRootURL
        self.replaceItem = replaceItem ?? { destination, source in
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: source,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        }
    }

    func saveRevision(
        using client: any SVNClientServing,
        workingCopyPath: String,
        relativePath: String,
        revision: String,
        destinationURL: URL,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    ) async throws {
        let destination = destinationURL.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let parentValues = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw RevisionFileError.invalidDestination
        }
        if fileManager.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw RevisionFileError.invalidDestination
            }
        }

        let staging = parent.appendingPathComponent(".svn-mac-revision-save-\(UUID().uuidString)")
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }
        _ = try await client.export(
            at: workingCopyPath,
            relativePath: relativePath,
            revision: revision,
            destinationPath: staging.path,
            force: false,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        let stagedValues = try staging.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard stagedValues.isRegularFile == true, stagedValues.isSymbolicLink != true else {
            throw RevisionFileError.invalidDestination
        }

        if fileManager.fileExists(atPath: destination.path) {
            try replaceItem(destination, staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    func restoreWorkingFile(
        contents: Data,
        workingCopyPath: String,
        relativePath: String,
        projectID: UUID,
        revision: String
    ) throws -> RevisionRestoreResult {
        let workingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let workingFile = try regularWorkingFile(
            workingCopy: workingCopy,
            relativePath: relativePath
        )
        let backupRootSource = try backupRootURL
            ?? SVNApplicationSupport.rootDirectory(fileManager: fileManager)
                .appendingPathComponent("Revision Restore Backups", isDirectory: true)
        let backupRoot = resolvedURL(backupRootSource)
        guard !SVNFileSystem.isAtOrBelow(backupRoot, root: workingCopy) else {
            throw RevisionFileError.backupRootInsideWorkingCopy
        }

        let sessionID = UUID().uuidString
        let finalDirectory = backupRoot
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let stagingDirectory = backupRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        var stagingDirectoryExists = true
        defer {
            if stagingDirectoryExists {
                try? fileManager.removeItem(at: stagingDirectory)
            }
        }

        let extensionSuffix = workingFile.pathExtension.isEmpty ? "" : ".\(workingFile.pathExtension)"
        let recoveryName = ".\(workingFile.deletingPathExtension().lastPathComponent)-before-r\(revision)\(extensionSuffix)"
        let stagedRecovery = stagingDirectory.appendingPathComponent(recoveryName)
        try fileManager.copyItem(at: workingFile, to: stagedRecovery)
        guard try SVNFileSystem.filesHaveEqualContents(workingFile, stagedRecovery) else {
            throw RevisionFileError.backupVerificationFailed
        }
        try fileManager.createDirectory(
            at: finalDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
        stagingDirectoryExists = false
        let recoveryURL = finalDirectory.appendingPathComponent(recoveryName)

        let stagedRevision = workingFile.deletingLastPathComponent()
            .appendingPathComponent(".svn-mac-revision-restore-\(UUID().uuidString)")
        var stagedRevisionExists = false
        defer {
            if stagedRevisionExists {
                try? fileManager.removeItem(at: stagedRevision)
            }
        }
        try contents.write(to: stagedRevision, options: .atomic)
        stagedRevisionExists = true
        guard try Data(contentsOf: stagedRevision) == contents else {
            throw RevisionFileError.replacementVerificationFailed
        }
        try replaceItem(workingFile, stagedRevision)
        stagedRevisionExists = false
        guard try Data(contentsOf: workingFile) == contents else {
            throw RevisionFileError.replacementVerificationFailed
        }
        return RevisionRestoreResult(recoveryURL: recoveryURL)
    }

    private func regularWorkingFile(workingCopy: URL, relativePath: String) throws -> URL {
        guard !(relativePath as NSString).isAbsolutePath, !relativePath.isEmpty else {
            throw RevisionFileError.pathOutsideWorkingCopy
        }
        let candidate = workingCopy.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = resolvedURL(candidate)
        guard SVNFileSystem.isAtOrBelow(resolved, root: workingCopy), resolved != workingCopy else {
            throw RevisionFileError.pathOutsideWorkingCopy
        }
        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw RevisionFileError.missingWorkingFile
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw RevisionFileError.unsafeWorkingFile
        }
        return resolved
    }

    private func resolvedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
