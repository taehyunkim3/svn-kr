import Foundation
import SVNCore

struct ConflictVersionBackup: Hashable {
    let url: URL
    let byteCount: Int64
    let modificationDate: Date?
    let revision: String?
}

struct ConflictResolutionSession: Identifiable, Hashable {
    let id: UUID
    let details: SVNConflictDetails
    let requestedPath: String
    let versionedPath: String
    let wasCanonicallyResolved: Bool
    let directoryURL: URL
    let mine: ConflictVersionBackup
    let server: ConflictVersionBackup
    let mineResolveSourceURL: URL?
}

enum ConflictFileError: Error {
    case unsupportedType(String)
    case missingMine
    case missingServer
    case missingWorkingFile
    case sourceOutsideWorkingCopy
    case backupRootInsideWorkingCopy
    case unsafeMineSource
    case unsafeServerSource
    case unsafeWorkingFile
    case workingRecoveryVerificationFailed
    case workingRestoreVerificationFailed
    case cleanupFailed(String)

}

/// SVN이 만든 충돌 보조 파일을 보존하고 사용자가 비교하기 쉬운 이름으로 복사합니다.
struct ConflictFileService {
    private let fileManager: FileManager
    private let backupRootURL: URL?
    private let copyItem: (URL, URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        backupRootURL: URL? = nil,
        copyItem: ((URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.backupRootURL = backupRootURL
        self.copyItem = copyItem ?? { source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func prepareSession(
        _ details: SVNConflictDetails,
        projectID: UUID,
        workingCopyPath: String,
        requestedPath: String? = nil,
        versionedPath: String? = nil
    ) throws -> ConflictResolutionSession {
        guard details.type == "text" else { throw ConflictFileError.unsupportedType(details.type) }
        // Real SVN binary conflicts may omit prev-wc-file because the working file itself
        // remains the mine version. Snapshot that file into the comparison session.
        let usesWorkingFileAsMine = details.myFile == nil
        let myFile = details.myFile ?? details.path
        guard let serverFile = details.serverFile else { throw ConflictFileError.missingServer }

        let supportRoot = try backupRootURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SVN Mac/Conflict Backups", isDirectory: true)
        let standardizedWorkingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let standardizedBackupRoot = resolvedURL(supportRoot)
        guard !isAtOrBelow(standardizedBackupRoot, root: standardizedWorkingCopy) else {
            throw ConflictFileError.backupRootInsideWorkingCopy
        }

        let mineSource = try sourceURL(
            myFile,
            workingCopy: standardizedWorkingCopy,
            missingError: .missingMine,
            unsafeError: .unsafeMineSource
        )
        let serverSource = try sourceURL(
            serverFile,
            workingCopy: standardizedWorkingCopy,
            missingError: .missingServer,
            unsafeError: .unsafeServerSource
        )

        let directory = standardizedBackupRoot
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingDirectory = standardizedBackupRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let original = URL(fileURLWithPath: details.path)
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        func fileName(_ suffix: String) -> String {
            ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
        }

        let mineFileName = fileName("내파일")
        let revisionSuffix = validRevision(details.serverRevision).map { "서버파일_r\($0)" } ?? "서버파일"
        let serverFileName = fileName(revisionSuffix)
        let stagedMineURL = stagingDirectory.appendingPathComponent(mineFileName)
        let stagedServerURL = stagingDirectory.appendingPathComponent(serverFileName)
        let stagedMineResolveSourceURL = stagingDirectory.appendingPathComponent(".mine-resolve-source")

        func backup(_ url: URL, revision: String?) throws -> ConflictVersionBackup {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return ConflictVersionBackup(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate,
                revision: revision
            )
        }

        do {
            try copyItem(mineSource, stagedMineURL)
            try copyItem(serverSource, stagedServerURL)
            if usesWorkingFileAsMine {
                try copyItem(stagedMineURL, stagedMineResolveSourceURL)
            }
            let mine = try backup(stagedMineURL, revision: nil)
            let server = try backup(stagedServerURL, revision: details.serverRevision)
            try fileManager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: stagingDirectory, to: directory)
            return ConflictResolutionSession(
                id: UUID(),
                details: details,
                requestedPath: requestedPath ?? details.path,
                versionedPath: versionedPath ?? details.path,
                wasCanonicallyResolved: Data((requestedPath ?? details.path).utf8)
                    != Data((versionedPath ?? details.path).utf8),
                directoryURL: directory,
                mine: ConflictVersionBackup(
                    url: directory.appendingPathComponent(mineFileName),
                    byteCount: mine.byteCount,
                    modificationDate: mine.modificationDate,
                    revision: mine.revision
                ),
                server: ConflictVersionBackup(
                    url: directory.appendingPathComponent(serverFileName),
                    byteCount: server.byteCount,
                    modificationDate: server.modificationDate,
                    revision: server.revision
                ),
                mineResolveSourceURL: usesWorkingFileAsMine
                    ? directory.appendingPathComponent(stagedMineResolveSourceURL.lastPathComponent)
                    : nil
            )
        } catch {
            do {
                try fileManager.removeItem(at: stagingDirectory)
            } catch {
                throw ConflictFileError.cleanupFailed(error.localizedDescription)
            }
            throw error
        }
    }

    /// 선택 시점의 실제 작업 파일을 숨김 복구본으로 보존한 뒤에만 resolve를 허용합니다.
    /// 비교 카드에 노출되는 mine/server 복사본과 달리 이 파일은 데이터 복구 전용입니다.
    func preserveWorkingFile(
        for session: ConflictResolutionSession,
        workingCopyPath: String
    ) throws -> URL {
        let workingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let source = try sourceURL(
            session.details.path,
            workingCopy: workingCopy,
            missingError: .missingWorkingFile,
            unsafeError: .unsafeWorkingFile
        )
        let recoveryID = UUID().uuidString
        let destination = session.directoryURL.appendingPathComponent(
            ".working-file-recovery-\(recoveryID)"
        )
        let staging = session.directoryURL.appendingPathComponent(
            ".working-file-recovery-\(recoveryID).staging"
        )
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }

        try copyItem(source, staging)
        guard try filesHaveEqualContents(source, staging) else {
            throw ConflictFileError.workingRecoveryVerificationFailed
        }

        try fileManager.moveItem(at: staging, to: destination)
        return destination
    }

    /// resolve 전 최신 작업 파일을 복구용으로 보존하고, SVN이 별도 binary mine
    /// artifact를 제공하지 않은 경우에는 준비 시점의 숨김 원본을 작업 파일에 복원합니다.
    func prepareWorkingFileForResolve(
        for session: ConflictResolutionSession,
        choice: SVNConflictChoice,
        workingCopyPath: String
    ) throws -> URL {
        let recoveryURL = try preserveWorkingFile(for: session, workingCopyPath: workingCopyPath)
        guard case .mineFull = choice, let mineSource = session.mineResolveSourceURL else {
            return recoveryURL
        }
        let workingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let workingFile = try sourceURL(
            session.details.path,
            workingCopy: workingCopy,
            missingError: .missingWorkingFile,
            unsafeError: .unsafeWorkingFile
        )
        try replaceFileAtomically(
            at: workingFile,
            with: mineSource,
            verificationError: .workingRestoreVerificationFailed
        )
        return recoveryURL
    }

    private func sourceURL(
        _ path: String,
        workingCopy: URL,
        missingError: ConflictFileError,
        unsafeError: ConflictFileError
    ) throws -> URL {
        let isAbsolute = (path as NSString).isAbsolutePath
        let candidate = (isAbsolute ? URL(fileURLWithPath: path) : workingCopy.appendingPathComponent(path))
            .standardizedFileURL
        let resolved = resolvedURL(candidate)
        if !isAtOrBelow(resolved, root: workingCopy) {
            throw ConflictFileError.sourceOutsideWorkingCopy
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: candidate.path)
        } catch {
            throw missingError
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw unsafeError
        }
        return resolved
    }

    private func resolvedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func isAtOrBelow(_ candidate: URL, root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func validRevision(_ revision: String?) -> String? {
        guard let revision, !revision.isEmpty,
              revision.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
            return nil
        }
        return revision
    }

    private func filesHaveEqualContents(_ first: URL, _ second: URL) throws -> Bool {
        let firstHandle = try FileHandle(forReadingFrom: first)
        let secondHandle = try FileHandle(forReadingFrom: second)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }
        let chunkSize = 64 * 1_024
        while true {
            let firstData = try firstHandle.read(upToCount: chunkSize) ?? Data()
            let secondData = try secondHandle.read(upToCount: chunkSize) ?? Data()
            guard firstData == secondData else { return false }
            if firstData.isEmpty { return true }
        }
    }

    private func replaceFileAtomically(
        at destination: URL,
        with source: URL,
        verificationError: ConflictFileError
    ) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(
            ".svn-mac-conflict-restore-\(UUID().uuidString)"
        )
        var stagingExists = false
        defer {
            if stagingExists {
                try? fileManager.removeItem(at: staging)
            }
        }
        try copyItem(source, staging)
        stagingExists = true
        guard try filesHaveEqualContents(source, staging) else { throw verificationError }
        _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: staging,
            backupItemName: nil,
            options: [.usingNewMetadataOnly]
        )
        stagingExists = false
        guard try filesHaveEqualContents(source, destination) else { throw verificationError }
    }

}
