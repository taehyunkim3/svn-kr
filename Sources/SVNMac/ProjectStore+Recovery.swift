import Foundation
import SVNCore

extension ProjectStore {
    func repairCanonicalAliases() async {
        guard let project = selectedProject else { return }
        errorMessage = nil
        let operationID = beginOperation(.recover(project.id))
        defer { endOperation(operationID) }
        do {
            _ = try await client.repairCanonicalAliases(
                at: project.path,
                credentials: try credentials(for: project)
            )
            guard selectedProjectID == project.id else { return }
            await refresh()
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }

    func beginPathRecovery() async {
        guard let project = selectedProject else { return }
        errorMessage = nil
        do {
            let preview = try await client.recoveryPreview(
                at: project.path,
                credentials: credentials(for: project)
            )
            guard selectedProjectID == project.id else { return }
            pathRecoverySourceProjectID = project.id
            pathRecoveryPreview = preview
            isShowingPathRecovery = true
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }

    func recoverWorkingCopy(to destinationURL: URL?) async -> Bool {
        guard let destinationURL,
              let sourceID = pathRecoverySourceProjectID,
              let sourceProject = projects.first(where: { $0.id == sourceID }) else { return false }
        let destination = destinationURL.standardizedFileURL
        guard !projects.contains(where: { $0.path == destination.path }) else {
            errorMessage = AppLanguage.current.localized(.ui.this.localWorkingFolderIsAlreadyRegistered)
            return false
        }

        errorMessage = nil
        let operationID = beginOperation(.recover(sourceID))
        defer { endOperation(operationID) }
        let recoveredID = UUID()
        do {
            let bookmarkData = try projectAccessManager.makeBookmark(for: destination)
            projectAccessManager.beginAccessing(destination, for: recoveredID)
            let sourceCredentials = try credentials(for: sourceProject)
            let result = try await client.recoverWorkingCopy(
                from: sourceProject.path,
                to: destination.path,
                credentials: sourceCredentials,
                allowUntrustedServerCertificate: sourceProject.allowsUntrustedServerCertificate == true,
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: sourceProject)
            )
            let recoveredURL = URL(fileURLWithPath: result.destinationPath, isDirectory: true).standardizedFileURL
            let recoveredProject = SVNProject(
                id: recoveredID,
                name: recoveredURL.lastPathComponent,
                path: recoveredURL.path,
                username: sourceProject.username,
                bookmarkData: bookmarkData,
                allowsUntrustedServerCertificate: sourceProject.allowsUntrustedServerCertificate == true
            )
            let recoveryIsStillCurrent = selectedProjectID == sourceID
                && pathRecoverySourceProjectID == sourceID
            projects.append(recoveredProject)

            if let password = sourceCredentials?.password, !password.isEmpty {
                sessionPasswords[recoveredID] = password
                try? credentialStore.setPassword(password, for: recoveredID)
            }

            guard recoveryIsStillCurrent else { return true }
            selectedProjectID = recoveredID
            await refresh()
            guard selectedProjectID == recoveredID else { return true }
            notice = AppLanguage.current.localized(.ui.path.recoveryCompletedTheOriginalWorkingFol)
            return true
        } catch {
            projectAccessManager.endAccessing(projectID: recoveredID)
            errorMessage = localizedError(error)
            return false
        }
    }
}
