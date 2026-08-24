import Foundation
import SVNCore

struct RepositoryPathNormalizationIssue {
    enum Kind: Equatable {
        case blockedByLocalChanges
        case blockedByLocks
        case invalidTargets
        case partiallyFailed
        case other
    }

    let kind: Kind
    let paths: [String]
    let result: SVNRepositoryPathNormalizationResult?
    let failedTarget: SVNRepositoryPathNormalizationTarget?
    let details: String?
}

extension ProjectStore {
    var allRepositoryPathNormalizationTargetsAreSelected: Bool {
        !repositoryPathNormalizationTargets.isEmpty
            && selectedRepositoryPathNormalizationTargets.count
                == repositoryPathNormalizationTargets.count
    }

    var canConfirmRepositoryPathNormalization: Bool {
        !selectedRepositoryPathNormalizationTargets.isEmpty
            && !repositoryPathNormalizationCommitMessage
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isRepositoryPathNormalizationRunning
    }

    func beginRepositoryPathNormalization() async {
        guard let project = selectedProject,
              !isRepositoryPathNormalizationRunning else { return }
        errorMessage = nil
        notice = nil
        repositoryPathNormalizationSourceProjectID = project.id
        repositoryPathNormalizationTargets = []
        selectedRepositoryPathNormalizationTargets = []
        repositoryPathNormalizationCommitMessage = AppLanguage.current.localized(
            "repository.path.normalization.default.commit.message"
        )
        repositoryPathNormalizationResult = nil
        repositoryPathNormalizationIssue = nil
        isConfirmingRepositoryPathNormalization = false
        isShowingRepositoryPathNormalization = true

        let operationID = beginOperation(.scanRepositoryPaths(project.id))
        defer { endOperation(operationID) }
        do {
            let targets = try await client.repositoryPathsNeedingNormalization(
                at: project.path,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate:
                    project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == project.id else { return }
            guard !targets.isEmpty else {
                notice = AppLanguage.current.localized(
                    "repository.path.normalization.no.paths"
                )
                isShowingRepositoryPathNormalization = false
                repositoryPathNormalizationSourceProjectID = nil
                return
            }
            repositoryPathNormalizationTargets = targets
            selectedRepositoryPathNormalizationTargets = Set(targets)
        } catch {
            guard selectedProjectID == project.id else { return }
            repositoryPathNormalizationIssue = RepositoryPathNormalizationIssue(
                kind: .other,
                paths: [],
                result: nil,
                failedTarget: nil,
                details: localizedError(error)
            )
        }
    }

    func toggleRepositoryPathNormalizationTarget(
        _ target: SVNRepositoryPathNormalizationTarget
    ) {
        if selectedRepositoryPathNormalizationTargets.contains(target) {
            selectedRepositoryPathNormalizationTargets.remove(target)
        } else {
            selectedRepositoryPathNormalizationTargets.insert(target)
        }
    }

    func setAllRepositoryPathNormalizationTargetsSelected(_ isSelected: Bool) {
        selectedRepositoryPathNormalizationTargets = isSelected
            ? Set(repositoryPathNormalizationTargets)
            : []
    }

    func requestRepositoryPathNormalizationConfirmation() {
        guard canConfirmRepositoryPathNormalization else { return }
        isConfirmingRepositoryPathNormalization = true
    }

    func normalizeSelectedRepositoryPaths() async {
        guard let projectID = repositoryPathNormalizationSourceProjectID,
              let project = projects.first(where: { $0.id == projectID }),
              selectedProjectID == projectID,
              isConfirmingRepositoryPathNormalization,
              canConfirmRepositoryPathNormalization else { return }
        let targets = repositoryPathNormalizationTargets.filter {
            selectedRepositoryPathNormalizationTargets.contains($0)
        }
        let message = repositoryPathNormalizationCommitMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
        isConfirmingRepositoryPathNormalization = false
        repositoryPathNormalizationResult = nil
        repositoryPathNormalizationIssue = nil
        errorMessage = nil

        let operationID = beginOperation(.normalizeRepositoryPaths(projectID))
        defer { endOperation(operationID) }
        do {
            let result = try await client.normalizeRepositoryPaths(
                targets,
                at: project.path,
                message: message,
                credentials: credentials(for: project),
                allowUntrustedServerCertificate:
                    project.allowsUntrustedServerCertificate == true
            )
            guard selectedProjectID == projectID else { return }
            repositoryPathNormalizationResult = result
            await update()
        } catch let error as SVNRepositoryPathNormalizationError {
            guard selectedProjectID == projectID else { return }
            await presentRepositoryPathNormalizationError(error, projectID: projectID)
        } catch {
            guard selectedProjectID == projectID else { return }
            repositoryPathNormalizationIssue = RepositoryPathNormalizationIssue(
                kind: .other,
                paths: [],
                result: nil,
                failedTarget: nil,
                details: localizedError(error)
            )
        }
    }

    private func presentRepositoryPathNormalizationError(
        _ error: SVNRepositoryPathNormalizationError,
        projectID: SVNProject.ID
    ) async {
        switch error {
        case let .blockedByLocalChanges(paths):
            repositoryPathNormalizationIssue = RepositoryPathNormalizationIssue(
                kind: .blockedByLocalChanges,
                paths: paths,
                result: nil,
                failedTarget: nil,
                details: nil
            )
        case let .blockedByLocks(paths):
            repositoryPathNormalizationIssue = RepositoryPathNormalizationIssue(
                kind: .blockedByLocks,
                paths: paths,
                result: nil,
                failedTarget: nil,
                details: nil
            )
        case let .invalidTargets(paths):
            repositoryPathNormalizationIssue = RepositoryPathNormalizationIssue(
                kind: .invalidTargets,
                paths: paths,
                result: nil,
                failedTarget: nil,
                details: nil
            )
        case let .failed(result, failedTarget, details):
            repositoryPathNormalizationResult = result
            repositoryPathNormalizationIssue = RepositoryPathNormalizationIssue(
                kind: .partiallyFailed,
                paths: [failedTarget.repositoryPath],
                result: result,
                failedTarget: failedTarget,
                details: details
            )
            if !result.renamedTargets.isEmpty, selectedProjectID == projectID {
                await update()
            }
        }
    }
}
