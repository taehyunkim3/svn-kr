import Foundation
import SVNCore

enum PropertyConflictResolutionChoice: String, Hashable, CaseIterable, Identifiable {
    case applyServerProperties
    case keepMyProperties

    var id: String { rawValue }

    var svnChoice: SVNConflictChoice {
        switch self {
        case .applyServerProperties: .theirsFull
        case .keepMyProperties: .mineFull
        }
    }
}

struct PropertyConflictSession: Identifiable, Hashable {
    let id: UUID
    let details: SVNConflictDetails
    let requestedPath: String
    let versionedPath: String
    let wasCanonicallyResolved: Bool
    let propertyNames: [String]

    init(
        id: UUID = UUID(),
        details: SVNConflictDetails,
        requestedPath: String,
        versionedPath: String,
        wasCanonicallyResolved: Bool,
        propertyNames: [String]
    ) {
        self.id = id
        self.details = details
        self.requestedPath = requestedPath
        self.versionedPath = versionedPath
        self.wasCanonicallyResolved = wasCanonicallyResolved
        self.propertyNames = propertyNames
    }
}

enum PropertyConflictResolution {
    static func verifyResolved(path: String, in snapshot: SVNWorkingCopySnapshot) throws {
        try verifyResolved(path: path, in: snapshot.statuses)
    }

    static func verifyResolved(path: String, in statuses: [SVNStatusEntry]) throws {
        let pathIdentity = SVNPathIdentity(rawPath: path)
        guard !statuses.contains(where: { entry in
            entry.propertyState == .conflicted
                && SVNPathIdentity(rawPath: entry.path) == pathIdentity
        }) else {
            throw ConflictFileError.conflictResolutionVerificationFailed
        }
    }
}

struct PropertyConflictService {
    private static let maximumPrejudiceFileSize = 1_048_576
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func propertyNames(
        workingCopyPath: String,
        versionedPath: String,
        nodeKind: SVNNodeKind?
    ) -> [String] {
        let workingCopyURL = URL(fileURLWithPath: workingCopyPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let targetURL = workingCopyURL
            .appendingPathComponent(versionedPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard SVNFileSystem.isAtOrBelow(targetURL, root: workingCopyURL) else { return [] }

        let candidates = prejudiceFileCandidates(for: targetURL, nodeKind: nodeKind)
        return Array(Set(candidates.flatMap(propertyNames(in:)))).sorted()
    }

    private func prejudiceFileCandidates(for targetURL: URL, nodeKind: SVNNodeKind?) -> [URL] {
        var isDirectory: ObjCBool = false
        let targetExists = fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory)
        let targetsDirectory = nodeKind == .directory || (targetExists && isDirectory.boolValue)
        let searchDirectory = targetsDirectory ? targetURL : targetURL.deletingLastPathComponent()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: searchDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.filter { candidate in
            guard candidate.pathExtension == "prej" else { return false }
            if !targetsDirectory,
               !candidate.lastPathComponent.hasPrefix(targetURL.lastPathComponent) {
                return false
            }
            guard let values = try? candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            ) else { return false }
            return values.isRegularFile == true
                && values.isSymbolicLink != true
                && (values.fileSize ?? Self.maximumPrejudiceFileSize + 1)
                    <= Self.maximumPrejudiceFileSize
        }
    }

    private func propertyNames(in fileURL: URL) -> [String] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return contents.components(separatedBy: .newlines).compactMap { line in
            guard let marker = line.range(of: "property '", options: .caseInsensitive) else {
                return nil
            }
            let remainder = line[marker.upperBound...]
            guard let closingQuote = remainder.firstIndex(of: "'") else { return nil }
            let name = String(remainder[..<closingQuote])
            return name.isEmpty ? nil : name
        }
    }
}
