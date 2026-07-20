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
    let directoryURL: URL
    let mine: ConflictVersionBackup
    let server: ConflictVersionBackup
}

enum ConflictFileError: LocalizedError {
    case unsupportedType(String)
    case missingMine
    case missingServer
    case sourceOutsideWorkingCopy
    case backupRootInsideWorkingCopy
    case unsafeMineSource
    case unsafeServerSource
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedType(type): "지원하지 않는 충돌 유형입니다: \(type)"
        case .missingMine: "내 파일 버전을 찾을 수 없습니다."
        case .missingServer: "서버 파일 버전을 찾을 수 없습니다."
        case .sourceOutsideWorkingCopy: "충돌 파일 경로가 작업 사본 밖을 가리킵니다."
        case .backupRootInsideWorkingCopy: "충돌 백업 위치는 작업 사본 밖에 있어야 합니다."
        case .unsafeMineSource: "내 파일 버전은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다."
        case .unsafeServerSource: "서버 파일 버전은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다."
        case let .cleanupFailed(message): "불완전한 충돌 백업 정리에 실패했습니다: \(message)"
        }
    }
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
        workingCopyPath: String
    ) throws -> ConflictResolutionSession {
        guard details.type == "text" else { throw ConflictFileError.unsupportedType(details.type) }
        guard let myFile = details.myFile else { throw ConflictFileError.missingMine }
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
            let mine = try backup(stagedMineURL, revision: nil)
            let server = try backup(stagedServerURL, revision: details.serverRevision)
            try fileManager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: stagingDirectory, to: directory)
            return ConflictResolutionSession(
                id: UUID(),
                details: details,
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
                )
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
        if !isAbsolute, !isAtOrBelow(resolved, root: workingCopy) {
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

}
