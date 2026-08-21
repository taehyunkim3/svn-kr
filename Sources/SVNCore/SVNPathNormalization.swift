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
        versionedPathsByCanonicalKey: [String: [String]] = [:],
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
            let pathComponents = components(of: relativePath)
            let protectedComponentCount = deepestVersionedAncestorComponentCount(
                of: pathComponents,
                versionedPathsByCanonicalKey: versionedPathsByCanonicalKey
            )
            var parentURL = rootURL
            var actualComponents: [String] = []
            var pathCouldBeResolved = true

            for (componentIndex, requestedComponent) in pathComponents.enumerated() {
                let requestedRelativePath = (actualComponents + [requestedComponent])
                    .joined(separator: "/")
                let result: EntryNormalization?
                if componentIndex < protectedComponentCount {
                    result = existingEntry(
                        named: requestedComponent,
                        in: parentURL
                    )
                } else {
                    result = normalizeEntries(
                        named: [requestedComponent],
                        in: parentURL,
                        fileManager: fileManager
                    )[0]
                }
                guard let result else {
                    reportUnnormalized(relativePath)
                    pathCouldBeResolved = false
                    break
                }

                actualComponents.append(result.actualName)
                if result.didRename { didRename = true }
                if !result.wasNormalized { reportUnnormalized(requestedRelativePath) }

                let childURL = parentURL.appendingPathComponent(result.actualName)
                if result.isSymbolicLink && actualComponents.count < pathComponents.count {
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

    private struct PendingRename {
        let index: Int
        let requestedName: String
        let sourceName: String
        let nfcName: String
        let isSymbolicLink: Bool
    }

    private static func existingEntry(
        named name: String,
        in parentURL: URL
    ) -> EntryNormalization? {
        let childURL = parentURL.appendingPathComponent(name)
        guard let values = try? childURL.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return nil
        }
        return EntryNormalization(
            actualName: name,
            isSymbolicLink: values.isSymbolicLink == true,
            didRename: false,
            wasNormalized: true
        )
    }

    private static func normalizeEntries(
        named requestedNames: [String],
        in parentURL: URL,
        initialEntries: [String]? = nil,
        fileManager: FileManager
    ) -> [EntryNormalization?] {
        let entries: [String]
        if let initialEntries {
            entries = initialEntries
        } else {
            guard let storedEntries = try? fileManager.contentsOfDirectory(atPath: parentURL.path) else {
                return Array(repeating: nil, count: requestedNames.count)
            }
            entries = storedEntries
        }
        var results = Array<EntryNormalization?>(repeating: nil, count: requestedNames.count)
        var pendingRenames: [PendingRename] = []
        let entryByBytes = Dictionary(
            entries.map { (Data($0.utf8), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var reservedDestinationBytes = Set(entryByBytes.keys)

        for (index, requestedName) in requestedNames.enumerated() {
            let requestedBytes = Data(requestedName.utf8)
            let nfcName = requestedName.precomposedStringWithCanonicalMapping
            let nfcBytes = Data(nfcName.utf8)
            guard let sourceName = entryByBytes[requestedBytes] ?? entryByBytes[nfcBytes] else {
                continue
            }
            let sourceURL = parentURL.appendingPathComponent(sourceName)
            let values = try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            let isSymbolicLink = values?.isSymbolicLink == true

            guard Data(sourceName.utf8) != nfcBytes else {
                results[index] = EntryNormalization(
                    actualName: sourceName,
                    isSymbolicLink: isSymbolicLink,
                    didRename: false,
                    wasNormalized: true
                )
                continue
            }

            guard !reservedDestinationBytes.contains(nfcBytes) else {
                results[index] = EntryNormalization(
                    actualName: sourceName,
                    isSymbolicLink: isSymbolicLink,
                    didRename: false,
                    wasNormalized: false
                )
                continue
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
            guard renameResult == 0 else {
                results[index] = EntryNormalization(
                    actualName: sourceName,
                    isSymbolicLink: isSymbolicLink,
                    didRename: false,
                    wasNormalized: false
                )
                continue
            }
            reservedDestinationBytes.insert(nfcBytes)
            pendingRenames.append(PendingRename(
                index: index,
                requestedName: requestedName,
                sourceName: sourceName,
                nfcName: nfcName,
                isSymbolicLink: isSymbolicLink
            ))
        }

        guard !pendingRenames.isEmpty else { return results }
        let storedEntries = (try? fileManager.contentsOfDirectory(atPath: parentURL.path)) ?? []
        let storedEntryByBytes = Dictionary(
            storedEntries.map { (Data($0.utf8), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let storedEntryByCanonicalBytes = Dictionary(
            storedEntries.map {
                (Data($0.precomposedStringWithCanonicalMapping.utf8), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for pending in pendingRenames {
            let requestedBytes = Data(pending.requestedName.utf8)
            let nfcBytes = Data(pending.nfcName.utf8)
            if let storedNFCName = storedEntryByBytes[nfcBytes] {
                results[pending.index] = EntryNormalization(
                    actualName: storedNFCName,
                    isSymbolicLink: pending.isSymbolicLink,
                    didRename: true,
                    wasNormalized: true
                )
                continue
            }

            // HFS+는 rename 성공 뒤에도 이름을 다시 NFD로 저장할 수 있습니다. 실제로 남은
            // 디렉터리 엔트리를 계속 사용하고, 커밋을 막지 않도록 실패만 보고합니다.
            let actualName = storedEntryByBytes[requestedBytes]
                ?? storedEntryByCanonicalBytes[nfcBytes]
                ?? pending.sourceName
            results[pending.index] = EntryNormalization(
                actualName: actualName,
                isSymbolicLink: pending.isSymbolicLink,
                didRename: false,
                wasNormalized: false
            )
        }
        return results
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

            let normalizationResults = normalizeEntries(
                named: childNames,
                in: directory.url,
                initialEntries: childNames,
                fileManager: fileManager
            )
            for (childName, result) in zip(childNames, normalizationResults) {
                let originalChildPath = directory.relativePath.isEmpty
                    ? childName
                    : directory.relativePath + "/" + childName
                guard let result else {
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

    private static func deepestVersionedAncestorComponentCount(
        of pathComponents: [String],
        versionedPathsByCanonicalKey: [String: [String]]
    ) -> Int {
        guard pathComponents.count > 1 else { return 0 }
        for count in stride(from: pathComponents.count - 1, through: 1, by: -1) {
            let prefix = pathComponents.prefix(count).joined(separator: "/")
            if versionedPathsByCanonicalKey[prefix.precomposedStringWithCanonicalMapping]?.count == 1 {
                return count
            }
        }
        return 0
    }
}
