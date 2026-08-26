import Foundation
import SVNCore

enum RevisionFileError: LocalizedError {
    case historyClientUnavailable
    case unsafeWorkingFile
    case unsafeWorkingFileParent
    case pathOutsideWorkingCopy
    case backupRootInsideWorkingCopy
    case backupVerificationFailed
    case replacementVerificationFailed
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .historyClientUnavailable:
            AppLanguage.current.localized(.ui.revision.projectSvnClientDoesNotSupportReadingHistoricalFileRevisions)
        case .unsafeWorkingFile:
            AppLanguage.current.localized(.ui.revision.workingFileMustRegularFileNotSymbolicLink)
        case .unsafeWorkingFileParent:
            AppLanguage.current.localized(.ui.revision.folderForRestoredFileNotDirectory)
        case .pathOutsideWorkingCopy:
            AppLanguage.current.localized(.ui.revision.filePathPointsOutsideLocalWorkingFolder)
        case .backupRootInsideWorkingCopy:
            AppLanguage.current.localized(.ui.revision.recoveryCopiesMustStoredOutsideLocalWorkingFolder)
        case .backupVerificationFailed:
            AppLanguage.current.localized(.ui.revision.currentWorkingFileCouldNotVerifiedRecoveryCopySoIt)
        case .replacementVerificationFailed:
            AppLanguage.current.localized(.ui.revision.restoredFileDidNotMatchSelectedRevisionByteByteRecovery)
        case .invalidDestination:
            AppLanguage.current.localized(.ui.revision.selectedSaveLocationNotSafeRegularFileDestination)
        }
    }
}

struct RevisionRestoreResult: Equatable {
    /// 되돌리기 직전의 작업 파일 복구본입니다.
    /// 작업 복사본에 파일이 없어 보존할 것이 없었으면 nil입니다.
    let recoveryURL: URL?
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

    /// 선택한 리비전의 내용을 작업 파일에 씁니다.
    /// 작업 복사본에 파일이 있으면 복구본을 남기고 원자적으로 교체합니다.
    /// 파일이 지워져 있으면 보존할 바이트가 없으므로 백업 없이 새로 씁니다.
    /// 이력에서 삭제된 파일을 되살리는 경로가 이 경우입니다.
    func restoreWorkingFile(
        contents: Data,
        workingCopyPath: String,
        relativePath: String,
        projectID: UUID,
        revision: String
    ) throws -> RevisionRestoreResult {
        let workingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let target = try workingFileTarget(workingCopy: workingCopy, relativePath: relativePath)
        let workingFile = target.url
        let recoveryURL = target.exists
            ? try preserveWorkingFile(
                workingFile,
                workingCopy: workingCopy,
                projectID: projectID,
                revision: revision
            )
            : nil

        // 파일과 함께 부모 폴더까지 지워졌을 수 있으므로 쓰기 전에 확인합니다.
        let parent = workingFile.deletingLastPathComponent()
        try prepareParentDirectory(parent)

        let stagedRevision = parent
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
        if target.exists {
            try replaceItem(workingFile, stagedRevision)
        } else {
            try fileManager.moveItem(at: stagedRevision, to: workingFile)
        }
        stagedRevisionExists = false
        guard try Data(contentsOf: workingFile) == contents else {
            throw RevisionFileError.replacementVerificationFailed
        }
        return RevisionRestoreResult(recoveryURL: recoveryURL)
    }

    /// 덮어쓰기 직전 바이트를 작업 복사본 밖에 복구본으로 남깁니다.
    private func preserveWorkingFile(
        _ workingFile: URL,
        workingCopy: URL,
        projectID: UUID,
        revision: String
    ) throws -> URL {
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
        return finalDirectory.appendingPathComponent(recoveryName)
    }

    /// 복원 대상이 될 수 있는 경로와 그 존재 여부입니다.
    private struct WorkingFileTarget {
        let url: URL
        let exists: Bool
    }

    /// 복원 대상을 작업 복사본 안의 경로로 한정합니다.
    /// 파일이 없는 것은 실패가 아니라 새로 써야 하는 상태입니다.
    private func workingFileTarget(
        workingCopy: URL,
        relativePath: String
    ) throws -> WorkingFileTarget {
        guard !(relativePath as NSString).isAbsolutePath, !relativePath.isEmpty else {
            throw RevisionFileError.pathOutsideWorkingCopy
        }
        let candidate = workingCopy.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = resolvedURL(candidate)
        guard SVNFileSystem.isAtOrBelow(resolved, root: workingCopy), resolved != workingCopy else {
            throw RevisionFileError.pathOutsideWorkingCopy
        }
        // attributesOfItem은 링크를 따라가지 않으므로 끊어진 심볼릭 링크도 걸러집니다.
        guard let attributes = try? fileManager.attributesOfItem(atPath: candidate.path) else {
            return WorkingFileTarget(url: resolved, exists: false)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RevisionFileError.unsafeWorkingFile
        }
        return WorkingFileTarget(url: resolved, exists: true)
    }

    /// 복원 대상의 부모 폴더를 확보합니다. 폴더가 아니면 쓰지 않고 멈춥니다.
    private func prepareParentDirectory(_ parent: URL) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: parent.path) else {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            return
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw RevisionFileError.unsafeWorkingFileParent
        }
    }

    private func resolvedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
