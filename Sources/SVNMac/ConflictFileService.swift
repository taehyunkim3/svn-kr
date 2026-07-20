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

    var errorDescription: String? {
        switch self {
        case let .unsupportedType(type): "지원하지 않는 충돌 유형입니다: \(type)"
        case .missingMine: "내 파일 버전을 찾을 수 없습니다."
        case .missingServer: "서버 파일 버전을 찾을 수 없습니다."
        }
    }
}

/// SVN이 만든 충돌 보조 파일을 보존하고 사용자가 비교하기 쉬운 이름으로 복사합니다.
struct ConflictFileService {
    private let fileManager: FileManager
    private let backupRootURL: URL?

    init(fileManager: FileManager = .default, backupRootURL: URL? = nil) {
        self.fileManager = fileManager
        self.backupRootURL = backupRootURL
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
        let directory = supportRoot
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: directory)
            }
        }

        func sourceURL(_ path: String) -> URL {
            if (path as NSString).isAbsolutePath {
                return URL(fileURLWithPath: path)
            }
            return URL(fileURLWithPath: workingCopyPath, isDirectory: true).appendingPathComponent(path)
        }

        let mineSource = sourceURL(myFile)
        let serverSource = sourceURL(serverFile)
        guard fileManager.fileExists(atPath: mineSource.path) else { throw ConflictFileError.missingMine }
        guard fileManager.fileExists(atPath: serverSource.path) else { throw ConflictFileError.missingServer }

        let original = URL(fileURLWithPath: details.path)
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        func fileName(_ suffix: String) -> String {
            ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
        }

        let mineURL = directory.appendingPathComponent(fileName("내파일"))
        let revisionSuffix = details.serverRevision.map { "서버파일_r\($0)" } ?? "서버파일"
        let serverURL = directory.appendingPathComponent(fileName(revisionSuffix))
        try fileManager.copyItem(at: mineSource, to: mineURL)
        try fileManager.copyItem(at: serverSource, to: serverURL)

        func backup(_ url: URL, revision: String?) throws -> ConflictVersionBackup {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return ConflictVersionBackup(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate,
                revision: revision
            )
        }

        let session = try ConflictResolutionSession(
            id: UUID(),
            details: details,
            directoryURL: directory,
            mine: backup(mineURL, revision: nil),
            server: backup(serverURL, revision: details.serverRevision)
        )
        completed = true
        return session
    }

    func backup(_ details: SVNConflictDetails, projectID: UUID, workingCopyPath: String) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("SVN Mac/Conflict Backups", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let original = URL(fileURLWithPath: workingCopyPath, isDirectory: true).appendingPathComponent(details.path)
        for source in [original.path, details.previousBaseFile, details.myFile, details.serverFile].compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: source) else { continue }
            let sourceURL = URL(fileURLWithPath: source)
            try fileManager.copyItem(at: sourceURL, to: uniqueURL(in: directory, named: sourceURL.lastPathComponent))
        }
        return directory
    }

    func preserveComparableVersions(_ details: SVNConflictDetails, workingCopyPath: String) throws -> [URL] {
        let original = URL(fileURLWithPath: workingCopyPath, isDirectory: true).appendingPathComponent(details.path)
        let directory = original.deletingLastPathComponent()
        let fileExtension = original.pathExtension
        let baseName = original.deletingPathExtension().lastPathComponent
        var results: [URL] = []

        if let myFile = details.myFile, fileManager.fileExists(atPath: myFile) {
            let name = suffixedName(baseName: baseName, suffix: "_내버전", fileExtension: fileExtension)
            let destination = uniqueURL(in: directory, named: name)
            try fileManager.copyItem(at: URL(fileURLWithPath: myFile), to: destination)
            results.append(destination)
        }
        if let serverFile = details.serverFile, fileManager.fileExists(atPath: serverFile) {
            let revision = details.serverRevision.map { "_r\($0)" } ?? ""
            let name = suffixedName(baseName: baseName, suffix: "_서버버전\(revision)", fileExtension: fileExtension)
            let destination = uniqueURL(in: directory, named: name)
            try fileManager.copyItem(at: URL(fileURLWithPath: serverFile), to: destination)
            results.append(destination)
        }
        return results
    }

    private func suffixedName(baseName: String, suffix: String, fileExtension: String) -> String {
        fileExtension.isEmpty ? baseName + suffix : "\(baseName)\(suffix).\(fileExtension)"
    }

    private func uniqueURL(in directory: URL, named name: String) -> URL {
        let initial = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let source = name as NSString
        let base = source.deletingPathExtension
        let ext = source.pathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
