import Foundation
import SVNCore

enum VersionedFileActionKind: String, Sendable {
    case move
    case copy
}

struct VersionedFileActionRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let kind: VersionedFileActionKind
    let sourceRelativePath: String
}

struct RepositoryRelocationRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let currentURL: String
    let connectionErrorMessage: String?
}

enum VersionedFileActionError: Error, Equatable {
    case invalidDestinationName
    case sourceIsNotVersioned(String)
    case sourceIsNotFile(String)
    case destinationExists(String)
    case destinationMatchesSource
}

enum RepositoryRelocationError: Error, Equatable {
    case invalidURL
    case unchangedURL
}

enum VersionedFileActionValidation {
    static func destinationRelativePath(
        sourceRelativePath: String,
        destinationName: String,
        sourceIsVersioned: Bool,
        destinationExists: Bool
    ) throws -> String {
        guard sourceIsVersioned else {
            throw VersionedFileActionError.sourceIsNotVersioned(sourceRelativePath)
        }
        let name = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              (name as NSString).lastPathComponent == name else {
            throw VersionedFileActionError.invalidDestinationName
        }
        let directory = (sourceRelativePath as NSString).deletingLastPathComponent
        let destination = directory.isEmpty ? name : directory + "/" + name
        guard Data(destination.utf8) != Data(sourceRelativePath.utf8) else {
            throw VersionedFileActionError.destinationMatchesSource
        }
        guard !destinationExists else {
            throw VersionedFileActionError.destinationExists(destination)
        }
        return destination
    }
}

enum RepositoryMaintenanceLocalization {
    static let requiredKeys = [
        "ui.current.repository.url.1a6f43d2",
        "ui.change.repository.location.8b21c7e4",
        "ui.repository.may.have.moved.31d0a5f8",
        "ui.open.repository.relocation.9c5e17a3",
        "ui.new.repository.url.5d4b9f02",
        "ui.local.changes.are.preserved.7e12c6a9",
        "ui.review.repository.relocation.2f8a41d0",
        "ui.confirm.repository.relocation.0c9d6e73",
        "ui.repository.relocation.summary.4a7e30b1",
        "ui.relocate.repository.6f3c2a98",
        "ui.relocating.repository.18b5d4e7",
        "ui.repository.relocation.failed.recovery.73a9e2c4",
        "ui.repository.relocated.4e1b8d60",
        "ui.rename.with.history.2a7c91e5",
        "ui.copy.with.history.5f0d3b82",
        "ui.new.file.name.8d41e6a0",
        "ui.file.action.commit.required.6c2b9e14",
        "ui.needs.lock.enable.0b7e4c91",
        "ui.needs.lock.disable.3d8a20f6",
        "ui.needs.lock.enabled.9a1f5c37",
        "ui.needs.lock.commit.required.4c6e82a1",
        "ui.invalid.file.name.7b2d10e9",
        "ui.source.is.not.versioned.1e9c4a72",
        "ui.source.is.not.file.6a3f8d20",
        "ui.destination.already.exists.5c0e71b4",
        "ui.destination.matches.source.2d9a64f1",
        "ui.invalid.repository.url.8e4c1a70",
        "ui.repository.url.unchanged.3a6d92e5",
    ]
}

extension ProjectStore {
    func loadSelectedRepositoryURL() async {
        guard let project = selectedProject else { return }
        do {
            let repositoryURL = try await client.workingCopyRepositoryURL(
                at: project.path,
                credentials: nil
            )
            guard selectedProjectID == project.id else { return }
            recoveryState.repositoryURL = repositoryURL
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }

    func requestRepositoryRelocation(connectionErrorMessage: String? = nil) async {
        guard let project = selectedProject else { return }
        let currentURL: String
        do {
            currentURL = try await client.workingCopyRepositoryURL(
                at: project.path,
                credentials: nil
            )
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
            return
        }
        guard selectedProjectID == project.id else { return }
        recoveryState.repositoryURL = currentURL
        recoveryState.repositoryRelocationFailureMessage = nil
        recoveryState.repositoryRelocationRequest = RepositoryRelocationRequest(
            projectID: project.id,
            currentURL: currentURL,
            connectionErrorMessage: connectionErrorMessage
        )
        isShowingCredentials = true
    }

    @discardableResult
    func captureRepositoryConnectionError(_ message: String) async -> Bool {
        guard SVNClient.isRepositoryConnectionError(message) else { return false }
        errorMessage = nil
        await requestRepositoryRelocation(connectionErrorMessage: message)
        return recoveryState.repositoryRelocationRequest != nil
    }

    @discardableResult
    func relocateSelectedRepository(to destinationURL: String) async -> Bool {
        guard let project = selectedProject,
              let request = recoveryState.repositoryRelocationRequest,
              request.projectID == project.id else { return false }
        let newURL = destinationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedURL = URL(string: newURL),
              let scheme = parsedURL.scheme?.lowercased(),
              ["file", "http", "https", "svn", "svn+ssh"].contains(scheme),
              scheme == "file" ? !parsedURL.path.isEmpty : parsedURL.host?.isEmpty == false else {
            recoveryState.repositoryRelocationFailureMessage = repositoryMaintenanceMessage(
                for: RepositoryRelocationError.invalidURL
            )
            return false
        }
        guard newURL != request.currentURL else {
            recoveryState.repositoryRelocationFailureMessage = repositoryMaintenanceMessage(
                for: RepositoryRelocationError.unchangedURL
            )
            return false
        }

        let operationID = beginOperation(.relocateRepository(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.relocate(
                at: project.path,
                fromRepositoryURL: request.currentURL,
                toRepositoryURL: newURL,
                credentials: credentials(for: project)
            )
            guard selectedProjectID == project.id else { return false }
            recoveryState.repositoryURL = newURL
            recoveryState.repositoryRelocationRequest = nil
            recoveryState.repositoryRelocationFailureMessage = nil
            clearAutomaticRefreshBlock(for: project.id)
            await refreshSelectedProject(manual: true)
            guard selectedProjectID == project.id else { return false }
            notice = AppLanguage.current.localized("ui.repository.relocated.4e1b8d60", newURL)
            return true
        } catch {
            guard selectedProjectID == project.id else { return false }
            let details = localizedError(error)
            recoveryState.repositoryRelocationFailureMessage = AppLanguage.current.localized(
                "ui.repository.relocation.failed.recovery.73a9e2c4",
                details
            )
            if let currentURL = try? await client.workingCopyRepositoryURL(
                at: project.path,
                credentials: nil
            ) {
                recoveryState.repositoryURL = currentURL
                recoveryState.repositoryRelocationRequest = RepositoryRelocationRequest(
                    projectID: project.id,
                    currentURL: currentURL,
                    connectionErrorMessage: request.connectionErrorMessage
                )
            }
            return false
        }
    }

    func requestVersionedFileAction(_ kind: VersionedFileActionKind, path: String) {
        guard let project = selectedProject else { return }
        recoveryState.versionedFileActionRequest = VersionedFileActionRequest(
            projectID: project.id,
            kind: kind,
            sourceRelativePath: path
        )
        recoveryState.versionedFileActionFailureMessage = nil
    }

    @discardableResult
    func performVersionedFileAction(
        _ request: VersionedFileActionRequest,
        destinationName: String
    ) async -> Bool {
        guard let project = selectedProject, request.projectID == project.id else { return false }
        let operationID = beginOperation(.versionedFileAction(project.id))
        defer { endOperation(operationID) }
        do {
            let entries = try await client.workingCopyEntries(at: project.path, credentials: nil)
            let sourceEntry = entries.first { pathsHaveSameBytes($0.path, request.sourceRelativePath) }
            let sourceIsVersioned = sourceEntry.map {
                $0.isVersioned || $0.status == "added" || $0.status == "replaced"
            } == true
            let candidateName = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceDirectory = (request.sourceRelativePath as NSString).deletingLastPathComponent
            let candidatePath = sourceDirectory.isEmpty
                ? candidateName
                : sourceDirectory + "/" + candidateName
            let destinationURL = URL(fileURLWithPath: project.path, isDirectory: true)
                .appendingPathComponent(candidatePath)
            let destinationExists = FileManager.default.fileExists(atPath: destinationURL.path)
                || entries.contains { pathsHaveSameBytes($0.path, candidatePath) }
            let destinationPath = try VersionedFileActionValidation.destinationRelativePath(
                sourceRelativePath: request.sourceRelativePath,
                destinationName: destinationName,
                sourceIsVersioned: sourceIsVersioned,
                destinationExists: destinationExists
            )
            let sourceURL = URL(fileURLWithPath: project.path, isDirectory: true)
                .appendingPathComponent(request.sourceRelativePath)
            let sourceValues = try sourceURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
                throw VersionedFileActionError.sourceIsNotFile(request.sourceRelativePath)
            }

            switch request.kind {
            case .move:
                _ = try await client.move(
                    at: project.path,
                    sourceRelativePath: request.sourceRelativePath,
                    destinationRelativePath: destinationPath,
                    credentials: nil
                )
            case .copy:
                _ = try await client.copy(
                    at: project.path,
                    sourceRelativePath: request.sourceRelativePath,
                    destinationRelativePath: destinationPath,
                    credentials: nil
                )
            }
            guard selectedProjectID == project.id else { return false }
            recoveryState.versionedFileActionRequest = nil
            recoveryState.versionedFileActionFailureMessage = nil
            selectedBrowserPath = destinationPath
            await refreshLocalWorkingCopy()
            await loadWorkingCopyFiles()
            guard selectedProjectID == project.id else { return false }
            notice = AppLanguage.current.localized(
                "ui.file.action.commit.required.6c2b9e14",
                destinationPath
            )
            return true
        } catch {
            guard selectedProjectID == project.id else { return false }
            recoveryState.versionedFileActionFailureMessage = repositoryMaintenanceMessage(for: error)
            return false
        }
    }

    func loadNeedsLockState(for paths: [String]) async {
        guard let project = selectedProject else { return }
        for path in uniquePaths(paths) {
            do {
                let properties = try await client.properties(
                    at: project.path,
                    relativePath: path,
                    credentials: nil
                )
                guard selectedProjectID == project.id else { return }
                recoveryState.needsLockPaths.remove(path)
                if properties.contains(where: { $0.name == "svn:needs-lock" }) {
                    recoveryState.needsLockPaths.insert(path)
                }
            } catch {
                guard selectedProjectID == project.id else { return }
                errorMessage = localizedError(error)
                return
            }
        }
    }

    @discardableResult
    func setNeedsLock(_ enabled: Bool, paths: [String]) async -> Bool {
        guard let project = selectedProject else { return false }
        let paths = uniquePaths(paths)
        guard !paths.isEmpty else { return false }
        let operationID = beginOperation(.needsLockProperty(project.id))
        defer { endOperation(operationID) }
        do {
            let entries = try await client.workingCopyEntries(at: project.path, credentials: nil)
            for path in paths {
                guard let entry = entries.first(where: { pathsHaveSameBytes($0.path, path) }),
                      entry.isVersioned || entry.status == "added" || entry.status == "replaced" else {
                    throw VersionedFileActionError.sourceIsNotVersioned(path)
                }
                let fileURL = URL(fileURLWithPath: project.path, isDirectory: true)
                    .appendingPathComponent(path)
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw VersionedFileActionError.sourceIsNotFile(path)
                }
            }

            for path in paths {
                let properties = try await client.properties(
                    at: project.path,
                    relativePath: path,
                    credentials: nil
                )
                let hasNeedsLock = properties.contains { $0.name == "svn:needs-lock" }
                if enabled, !hasNeedsLock {
                    _ = try await client.setProperty(
                        named: "svn:needs-lock",
                        value: Data("*".utf8),
                        at: project.path,
                        relativePath: path,
                        credentials: nil
                    )
                } else if !enabled, hasNeedsLock {
                    _ = try await client.deleteProperty(
                        named: "svn:needs-lock",
                        at: project.path,
                        relativePath: path,
                        credentials: nil
                    )
                }
            }
            guard selectedProjectID == project.id else { return false }
            if enabled {
                recoveryState.needsLockPaths.formUnion(paths)
            } else {
                recoveryState.needsLockPaths.subtract(paths)
            }
            await refreshLocalWorkingCopy()
            guard selectedProjectID == project.id else { return false }
            notice = AppLanguage.current.localized(
                "ui.needs.lock.commit.required.4c6e82a1",
                paths.count
            )
            return true
        } catch {
            guard selectedProjectID == project.id else { return false }
            await loadNeedsLockState(for: paths)
            await refreshLocalWorkingCopy()
            errorMessage = repositoryMaintenanceMessage(for: error)
            return false
        }
    }

    private func repositoryMaintenanceMessage(for error: Error) -> String {
        switch error {
        case VersionedFileActionError.invalidDestinationName:
            AppLanguage.current.localized("ui.invalid.file.name.7b2d10e9")
        case let VersionedFileActionError.sourceIsNotVersioned(path):
            AppLanguage.current.localized("ui.source.is.not.versioned.1e9c4a72", path)
        case let VersionedFileActionError.sourceIsNotFile(path):
            AppLanguage.current.localized("ui.source.is.not.file.6a3f8d20", path)
        case let VersionedFileActionError.destinationExists(path):
            AppLanguage.current.localized("ui.destination.already.exists.5c0e71b4", path)
        case VersionedFileActionError.destinationMatchesSource:
            AppLanguage.current.localized("ui.destination.matches.source.2d9a64f1")
        case RepositoryRelocationError.invalidURL:
            AppLanguage.current.localized("ui.invalid.repository.url.8e4c1a70")
        case RepositoryRelocationError.unchangedURL:
            AppLanguage.current.localized("ui.repository.url.unchanged.3a6d92e5")
        default:
            localizedError(error)
        }
    }

    private func pathsHaveSameBytes(_ lhs: String, _ rhs: String) -> Bool {
        Data(lhs.utf8) == Data(rhs.utf8)
    }

    private func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<Data> = []
        return paths.filter { seen.insert(Data($0.utf8)).inserted }
    }
}
