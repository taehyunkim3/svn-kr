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
    let isBinary: Bool
    /// 같은 경로에 속성 충돌이 함께 걸려 있는지입니다.
    /// `svn resolve`는 한 번의 선택으로 내용과 속성 충돌을 같은 방향으로 함께 해결합니다.
    let hasPropertyConflict: Bool
    let propertyNames: [String]
}

/// 하위 트리를 통째로 되돌리기 전에 만들어 두는 복구본입니다.
struct ConflictSubtreeBackup: Hashable {
    let directoryURL: URL
    let fileCount: Int
    let byteCount: Int64
}

/// 한 경로에 내용 충돌과 속성 충돌이 동시에 날 수 있습니다.
/// `svn info --xml`은 충돌마다 `<conflict>` 요소를 따로 내보내지만 파서는 마지막 요소만
/// 남기므로 `details.type`만으로는 분류를 신뢰할 수 없습니다. 같은 경로의 `svn status`
/// 항목 상태(`item`)와 속성 상태(`props`)를 함께 보고 판정합니다.
enum ConflictClassification: Hashable {
    case text(hasPropertyConflict: Bool)
    case tree
    case property
    case unsupported(String)

    /// 판정은 `svn info --xml` 이 내보낸 충돌 목록을 먼저 봅니다.
    /// `svn status` 교차 판정은 아래 두 경우 때문에 남겨 둡니다.
    /// - 등록 프로젝트가 작업 복사본 하위 폴더면 `SVNClient` 가 경로 접두사를 떼며
    ///   `SVNConflictDetails` 를 평면 필드로 다시 만들어, 충돌 목록이 대표 유형 하나로 줄어듭니다.
    /// - `svn info` 가 충돌 요소를 내보내지 않는데 `svn status` 는 충돌로 보고하는 상태가 있습니다.
    /// 둘 다 내용 충돌을 속성 충돌로 오분류해 작업 파일을 백업 없이 덮어쓰게 만드는 입력입니다.
    static func classify(
        details: SVNConflictDetails,
        statusItem: SVNStatusKind?,
        propertyState: SVNPropertyState
    ) -> ConflictClassification {
        if details.hasTreeConflict { return .tree }
        let hasPropertyConflict = details.hasPropertyConflict || propertyState == .conflicted
        if details.hasTextConflict || statusItem == .conflicted {
            return .text(hasPropertyConflict: hasPropertyConflict)
        }
        if hasPropertyConflict { return .property }
        return .unsupported(details.type)
    }

    /// `svn status` 만 내용 충돌을 알려준 경우 내용 충돌 보호 경로로 보내기 위해 유형을 바로잡습니다.
    /// 보조 파일 경로(`myFile`/`serverFile`)는 파서가 채운 값을 그대로 씁니다.
    static func textConflictDetails(from details: SVNConflictDetails) -> SVNConflictDetails {
        guard details.type != "text" else { return details }
        return SVNConflictDetails(
            path: details.path,
            type: "text",
            operation: details.operation,
            previousBaseFile: details.previousBaseFile,
            myFile: details.myFile,
            serverFile: details.serverFile,
            previousRevision: details.previousRevision,
            serverRevision: details.serverRevision
        )
    }
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
    case conflictResolutionVerificationFailed
    case cleanupFailed(String)

}

/// SVN이 만든 충돌 보조 파일을 보존하고 사용자가 비교하기 쉬운 이름으로 복사합니다.
struct ConflictFileService {
    private static let binaryInspectionByteCount = 8_000
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
        versionedPath: String? = nil,
        hasPropertyConflict: Bool = false,
        propertyNames: [String] = []
    ) throws -> ConflictResolutionSession {
        guard details.type == "text" else { throw ConflictFileError.unsupportedType(details.type) }
        // Real SVN binary conflicts may omit prev-wc-file because the working file itself
        // remains the mine version. Snapshot that file into the comparison session.
        let usesWorkingFileAsMine = details.myFile == nil
        let myFile = details.myFile ?? details.path
        guard let serverFile = details.serverFile else { throw ConflictFileError.missingServer }

        let supportRoot = try backupRootURL
            ?? SVNApplicationSupport.rootDirectory(fileManager: fileManager)
                .appendingPathComponent("Conflict Backups", isDirectory: true)
        let standardizedWorkingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let standardizedBackupRoot = resolvedURL(supportRoot)
        guard !SVNFileSystem.isAtOrBelow(standardizedBackupRoot, root: standardizedWorkingCopy) else {
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
            let isBinary = inspectBinaryBackup(server: stagedServerURL, mine: stagedMineURL)
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
                    : nil,
                isBinary: isBinary,
                hasPropertyConflict: hasPropertyConflict,
                propertyNames: propertyNames
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
        guard try SVNFileSystem.filesHaveEqualContents(source, staging) else {
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

    /// 하위 트리를 통째로 되돌리기 전에 그 아래 모든 정규 파일을 복구본으로 복사합니다.
    /// `svn revert --depth infinity`는 버전관리되지 않은 파일까지 지우므로,
    /// SVN 상태로 걸러내지 않고 `.svn`을 뺀 전부를 바이트 검증과 함께 보존합니다.
    /// 대상이 파일 하나이면 그 파일만 보존합니다. 보존할 파일이 없으면 nil을 반환합니다.
    func preserveSubtree(
        relativePath: String,
        projectID: UUID,
        workingCopyPath: String
    ) throws -> ConflictSubtreeBackup? {
        let workingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        let supportRoot = try backupRootURL
            ?? SVNApplicationSupport.rootDirectory(fileManager: fileManager)
                .appendingPathComponent("Conflict Backups", isDirectory: true)
        let standardizedBackupRoot = resolvedURL(supportRoot)
        guard !SVNFileSystem.isAtOrBelow(standardizedBackupRoot, root: workingCopy) else {
            throw ConflictFileError.backupRootInsideWorkingCopy
        }
        let files = subtreeRegularFiles(relativePath: relativePath, workingCopy: workingCopy)
        guard !files.isEmpty else { return nil }

        let destination = standardizedBackupRoot
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingDirectory = standardizedBackupRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            var byteCount: Int64 = 0
            for file in files {
                let stagedURL = stagingDirectory.appendingPathComponent(file.relativePath)
                try fileManager.createDirectory(
                    at: stagedURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try copyItem(file.url, stagedURL)
                guard try SVNFileSystem.filesHaveEqualContents(file.url, stagedURL) else {
                    throw ConflictFileError.workingRecoveryVerificationFailed
                }
                byteCount += Int64(
                    (try? stagedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                )
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: stagingDirectory, to: destination)
            return ConflictSubtreeBackup(
                directoryURL: destination,
                fileCount: files.count,
                byteCount: byteCount
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    /// 되돌리기 확인창이 "무엇이 사라지는지"를 경로로 보여줄 수 있도록,
    /// 버전관리되지 않은 디렉터리 안의 파일 경로를 펼쳐 줍니다.
    /// `svn status`는 미버전 디렉터리를 항목 하나로만 보고합니다.
    func containedFilePaths(relativePath: String, workingCopyPath: String) -> [String] {
        let workingCopy = resolvedURL(URL(fileURLWithPath: workingCopyPath, isDirectory: true))
        var isDirectory: ObjCBool = false
        let target = workingCopy.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return [] }
        return subtreeRegularFiles(relativePath: relativePath, workingCopy: workingCopy)
            .map(\.relativePath)
    }

    /// 작업 복사본 루트 기준 상대 경로로 하위의 정규 파일을 모읍니다.
    /// `.svn` 메타데이터와 심볼릭 링크는 제외합니다.
    private func subtreeRegularFiles(
        relativePath: String,
        workingCopy: URL
    ) -> [(url: URL, relativePath: String)] {
        let target = workingCopy.appendingPathComponent(relativePath).standardizedFileURL
        guard SVNFileSystem.isAtOrBelow(resolvedURL(target), root: workingCopy) else { return [] }
        guard let attributes = try? fileManager.attributesOfItem(atPath: target.path),
              let type = attributes[.type] as? FileAttributeType else { return [] }
        if type == .typeRegular {
            return [(target, relativePath)]
        }
        guard type == .typeDirectory else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: target,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }

        let basePath = target.path
        var results: [(url: URL, relativePath: String)] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".svn" {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            ), values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(basePath + "/") else { continue }
            let suffix = String(path.dropFirst(basePath.count + 1))
            results.append((url, relativePath + "/" + suffix))
        }
        return results.sorted { $0.relativePath < $1.relativePath }
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
        if !SVNFileSystem.isAtOrBelow(resolved, root: workingCopy) {
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

    private func validRevision(_ revision: String?) -> String? {
        guard let revision, !revision.isEmpty,
              revision.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
            return nil
        }
        return revision
    }

    private func inspectBinaryBackup(server: URL, mine: URL) -> Bool {
        let source = fileManager.fileExists(atPath: server.path) ? server : mine
        do {
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount: Self.binaryInspectionByteCount) ?? Data()
            return prefix.contains(0)
        } catch {
            return true
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
        guard try SVNFileSystem.filesHaveEqualContents(source, staging) else { throw verificationError }
        _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: staging,
            backupItemName: nil,
            options: [.usingNewMetadataOnly]
        )
        stagingExists = false
        guard try SVNFileSystem.filesHaveEqualContents(source, destination) else { throw verificationError }
    }

}
