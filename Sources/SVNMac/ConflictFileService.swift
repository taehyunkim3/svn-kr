import Foundation
import SVNCore

/// SVN이 만든 충돌 보조 파일을 보존하고 사용자가 비교하기 쉬운 이름으로 복사합니다.
struct ConflictFileService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

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
