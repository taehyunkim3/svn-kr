import Foundation
import Darwin

struct SVNPathNormalizationResult: Sendable, Equatable {
    let normalizedPaths: [String]
    let unnormalizedPaths: [String]
    let didRename: Bool
}

enum SVNPathNormalization {
    static func normalizeNewPaths(
        rootPath: String,
        relativePaths: [String],
        fileManager: FileManager = .default
    ) -> SVNPathNormalizationResult {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let orderedPaths = relativePaths.enumerated().sorted { lhs, rhs in
            let lhsDepth = components(of: lhs.element).count
            let rhsDepth = components(of: rhs.element).count
            return lhsDepth == rhsDepth ? lhs.offset < rhs.offset : lhsDepth < rhsDepth
        }
        var normalizedByIndex: [Int: String] = [:]
        var unnormalizedPaths: [String] = []
        var unnormalizedPathBytes: Set<Data> = []
        var didRename = false

        func reportUnnormalized(_ path: String) {
            guard unnormalizedPathBytes.insert(Data(path.utf8)).inserted else { return }
            unnormalizedPaths.append(path)
        }

        for (index, relativePath) in orderedPaths {
            var parentURL = rootURL
            var actualComponents: [String] = []
            var pathCouldBeResolved = true

            for requestedComponent in components(of: relativePath) {
                let requestedRelativePath = (actualComponents + [requestedComponent])
                    .joined(separator: "/")
                guard let result = normalizeEntry(
                    named: requestedComponent,
                    in: parentURL,
                    fileManager: fileManager
                ) else {
                    reportUnnormalized(relativePath)
                    pathCouldBeResolved = false
                    break
                }

                actualComponents.append(result.actualName)
                if result.didRename { didRename = true }
                if !result.wasNormalized { reportUnnormalized(requestedRelativePath) }

                let childURL = parentURL.appendingPathComponent(result.actualName)
                if result.isSymbolicLink && actualComponents.count < components(of: relativePath).count {
                    reportUnnormalized(relativePath)
                    pathCouldBeResolved = false
                    break
                }
                parentURL = childURL
            }

            guard pathCouldBeResolved else {
                normalizedByIndex[index] = relativePath
                continue
            }

            let normalizedPath = actualComponents.isEmpty ? relativePath : actualComponents.joined(separator: "/")
            normalizedByIndex[index] = normalizedPath

            guard let values = try? parentURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ), values.isDirectory == true, values.isSymbolicLink != true else {
                continue
            }
            normalizeDescendants(
                of: parentURL,
                relativePath: normalizedPath,
                fileManager: fileManager,
                didRename: &didRename,
                reportUnnormalized: reportUnnormalized
            )
        }

        return SVNPathNormalizationResult(
            normalizedPaths: relativePaths.indices.map { normalizedByIndex[$0] ?? relativePaths[$0] },
            unnormalizedPaths: unnormalizedPaths,
            didRename: didRename
        )
    }

    private struct EntryNormalization {
        let actualName: String
        let isSymbolicLink: Bool
        let didRename: Bool
        let wasNormalized: Bool
    }

    private static func normalizeEntry(
        named requestedName: String,
        in parentURL: URL,
        fileManager: FileManager
    ) -> EntryNormalization? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: parentURL.path) else {
            return nil
        }
        let requestedBytes = Data(requestedName.utf8)
        let nfcName = requestedName.precomposedStringWithCanonicalMapping
        let nfcBytes = Data(nfcName.utf8)
        guard let sourceName = entries.first(where: { Data($0.utf8) == requestedBytes })
                ?? entries.first(where: { Data($0.utf8) == nfcBytes }) else {
            return nil
        }
        let sourceURL = parentURL.appendingPathComponent(sourceName)
        let values = try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        let isSymbolicLink = values?.isSymbolicLink == true

        guard Data(sourceName.utf8) != nfcBytes else {
            return EntryNormalization(
                actualName: sourceName,
                isSymbolicLink: isSymbolicLink,
                didRename: false,
                wasNormalized: true
            )
        }

        if entries.contains(where: { Data($0.utf8) == nfcBytes }) {
            return EntryNormalization(
                actualName: sourceName,
                isSymbolicLink: isSymbolicLink,
                didRename: false,
                wasNormalized: false
            )
        }

        // FileManager가 URL을 파일시스템 표현으로 바꾸는 과정에서 한글을 NFD로 만들 수
        // 있으므로, APFS에 NFC 목적지 바이트를 그대로 전달하도록 rename(2)를 사용합니다.
        let sourcePath = parentURL.path + "/" + sourceName
        let destinationPath = parentURL.path + "/" + nfcName
        let renameResult = sourcePath.withCString { sourcePointer in
            destinationPath.withCString { destinationPointer in
                Darwin.rename(sourcePointer, destinationPointer)
            }
        }
        if renameResult != 0 {
            return EntryNormalization(
                actualName: sourceName,
                isSymbolicLink: isSymbolicLink,
                didRename: false,
                wasNormalized: false
            )
        }

        let storedEntries = (try? fileManager.contentsOfDirectory(atPath: parentURL.path)) ?? []
        if let storedNFCName = storedEntries.first(where: { Data($0.utf8) == nfcBytes }) {
            return EntryNormalization(
                actualName: storedNFCName,
                isSymbolicLink: isSymbolicLink,
                didRename: true,
                wasNormalized: true
            )
        }

        // HFS+는 rename 성공 뒤에도 이름을 다시 NFD로 저장할 수 있습니다. 실제로 남은
        // 디렉터리 엔트리를 계속 사용하고, 커밋을 막지 않도록 실패만 보고합니다.
        let actualName = storedEntries.first(where: { Data($0.utf8) == requestedBytes })
            ?? storedEntries.first(where: {
                Data($0.precomposedStringWithCanonicalMapping.utf8) == nfcBytes
            })
            ?? sourceName
        return EntryNormalization(
            actualName: actualName,
            isSymbolicLink: isSymbolicLink,
            didRename: false,
            wasNormalized: false
        )
    }

    private static func normalizeDescendants(
        of directoryURL: URL,
        relativePath: String,
        fileManager: FileManager,
        didRename: inout Bool,
        reportUnnormalized: (String) -> Void
    ) {
        var pendingDirectories: [(url: URL, relativePath: String)] = [(directoryURL, relativePath)]
        var nextIndex = 0

        while nextIndex < pendingDirectories.count {
            let directory = pendingDirectories[nextIndex]
            nextIndex += 1
            guard let childNames = try? fileManager.contentsOfDirectory(atPath: directory.url.path) else {
                reportUnnormalized(directory.relativePath)
                continue
            }

            for childName in childNames {
                let originalChildPath = directory.relativePath.isEmpty
                    ? childName
                    : directory.relativePath + "/" + childName
                guard let result = normalizeEntry(
                    named: childName,
                    in: directory.url,
                    fileManager: fileManager
                ) else {
                    reportUnnormalized(originalChildPath)
                    continue
                }
                if result.didRename { didRename = true }
                if !result.wasNormalized { reportUnnormalized(originalChildPath) }

                let childURL = directory.url.appendingPathComponent(result.actualName)
                guard !result.isSymbolicLink,
                      let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else {
                    continue
                }
                let actualChildPath = directory.relativePath.isEmpty
                    ? result.actualName
                    : directory.relativePath + "/" + result.actualName
                pendingDirectories.append((childURL, actualChildPath))
            }
        }
    }

    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
