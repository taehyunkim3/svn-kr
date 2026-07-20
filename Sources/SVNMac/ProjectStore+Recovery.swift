import Foundation
import SVNCore

extension ProjectStore {
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
            errorMessage = AppLanguage.current.text(
                "이미 등록된 로컬 작업 폴더입니다.",
                "This local working folder is already registered."
            )
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
                allowUntrustedServerCertificate: sourceProject.allowsUntrustedServerCertificate == true
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
            projects.append(recoveredProject)

            if let password = sourceCredentials?.password, !password.isEmpty {
                sessionPasswords[recoveredID] = password
                try? credentialStore.setPassword(password, for: recoveredID)
            }

            selectedProjectID = recoveredID
            await refresh()
            notice = AppLanguage.current.text(
                "경로 복구 완료 — 원본 작업 폴더는 그대로 유지했습니다.",
                "Path recovery completed. The original working folder was preserved."
            )
            return true
        } catch {
            projectAccessManager.endAccessing(projectID: recoveredID)
            errorMessage = localizedError(error)
            return false
        }
    }
}
