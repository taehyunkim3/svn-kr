import Foundation
import SVNCore

struct WorkingCopyCleanupRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: SVNProject.ID
    let path: String
    let originalMessage: String
}

struct CanceledCheckoutRecoveryRequest: Identifiable, Equatable {
    let id: SVNProject.ID
    let destinationPath: String
    let username: String?
    let bookmarkData: Data
    let canEmptySafely: Bool
    let allowsUntrustedServerCertificate: Bool
}

extension ProjectStore {
    @discardableResult
    func offerWorkingCopyCleanup(for error: Error, projectID: SVNProject.ID) -> Bool {
        guard SVNClient.needsCleanup(error),
              let project = projects.first(where: { $0.id == projectID }) else { return false }
        workingCopyCleanupRequest = WorkingCopyCleanupRequest(
            projectID: project.id,
            path: project.path,
            originalMessage: SVNErrorLocalization.diagnosticDetails(for: error)
        )
        errorMessage = nil
        isShowingUpdatePreview = false
        isShowingLocks = false
        isShowingTemporaryFileCleanup = false
        isShowingCredentials = true
        return true
    }

    func requestSelectedWorkingCopyCleanup() {
        guard let project = selectedProject else { return }
        workingCopyCleanupRequest = WorkingCopyCleanupRequest(
            projectID: project.id,
            path: project.path,
            originalMessage: ""
        )
    }

    func dismissWorkingCopyCleanupRequest() {
        workingCopyCleanupRequest = nil
    }

    @discardableResult
    func cleanupSelectedWorkingCopy() async -> Bool {
        guard let project = selectedProject else { return false }
        return await cleanupWorkingCopy(project: project)
    }

    @discardableResult
    private func cleanupWorkingCopy(project: SVNProject) async -> Bool {
        guard !activeOperations.contains(where: { $0.kind == .cleanupWorkingCopy(project.path) }) else {
            return false
        }
        let operationID = beginOperation(.cleanupWorkingCopy(project.path))
        defer { endOperation(operationID) }
        do {
            let result = try await client.cleanup(
                at: project.path,
                credentials: credentials(for: project)
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedProjectID == project.id,
                  projects.contains(where: { $0.id == project.id && $0.path == project.path }) else {
                return false
            }
            workingCopyCleanupRequest = nil
            clearAutomaticRefreshBlock(for: project.id)
            notice = AppLanguage.current.localized(
                "ui.working.copy.cleanup.completed.11c93f4a",
                result
            )
            return true
        } catch {
            guard selectedProjectID == project.id,
                  projects.contains(where: { $0.id == project.id && $0.path == project.path }) else {
                return false
            }
            workingCopyCleanupRequest = nil
            errorMessage = AppLanguage.current.localized(
                "ui.working.copy.cleanup.failed.contact.support.81a7d2ce",
                SVNErrorLocalization.diagnosticDetails(for: error)
            )
            return false
        }
    }

    func prepareCanceledCheckoutRecovery(
        id: SVNProject.ID,
        destination: URL,
        username: String,
        password: String,
        bookmarkData: Data,
        canEmptySafely: Bool,
        allowsUntrustedServerCertificate: Bool,
        credentials: SVNCredentials?
    ) async -> Bool {
        let client = client
        let destinationPath = destination.path
        let isWorkingCopy = await Task.detached {
            do {
                try await client.validateWorkingCopy(at: destinationPath, credentials: credentials)
                return true
            } catch {
                return false
            }
        }.value
        guard isWorkingCopy else { return false }

        if !password.isEmpty {
            sessionPasswords[id] = password
        }
        canceledCheckoutRecoveryRequest = CanceledCheckoutRecoveryRequest(
            id: id,
            destinationPath: destinationPath,
            username: username.isEmpty ? nil : username,
            bookmarkData: bookmarkData,
            canEmptySafely: canEmptySafely,
            allowsUntrustedServerCertificate: allowsUntrustedServerCertificate
        )
        return true
    }

    @discardableResult
    func resumeCanceledCheckout(_ request: CanceledCheckoutRecoveryRequest) async -> Bool {
        guard canceledCheckoutRecoveryRequest?.id == request.id,
              !projects.contains(where: { $0.path == request.destinationPath }),
              !activeOperations.contains(where: {
                  $0.kind == .recoverCanceledCheckout(request.destinationPath)
              }) else { return false }
        let recoveryOperationID = beginOperation(.recoverCanceledCheckout(request.destinationPath))
        defer { endOperation(recoveryOperationID) }
        do {
            try await client.validateWorkingCopy(
                at: request.destinationPath,
                credentials: pendingCheckoutCredentials(for: request)
            )
        } catch {
            errorMessage = AppLanguage.current.localized(
                "ui.checkout.recovery.validation.failed.5fd4218c",
                SVNErrorLocalization.diagnosticDetails(for: error)
            )
            return false
        }

        let project = SVNProject(
            id: request.id,
            name: URL(fileURLWithPath: request.destinationPath).lastPathComponent,
            path: request.destinationPath,
            username: request.username,
            bookmarkData: request.bookmarkData,
            allowsUntrustedServerCertificate: request.allowsUntrustedServerCertificate
        )
        registerRecoveredCheckout(project)
        canceledCheckoutRecoveryRequest = nil
        isShowingAddRepository = false

        if let password = sessionPasswords[project.id], !password.isEmpty {
            do {
                try credentialStore.setPassword(password, for: project.id)
            } catch {
                notice = AppLanguage.current.localized(
                    "ui.checkout.completed.but.the.password.could.not.be.ed5274e5",
                    localizedError(error)
                )
            }
        }

        if await cleanupWorkingCopy(project: project) {
            await update()
        }
        return true
    }

    func emptyCanceledCheckout(_ request: CanceledCheckoutRecoveryRequest) async {
        guard canceledCheckoutRecoveryRequest?.id == request.id,
              request.canEmptySafely,
              !activeOperations.contains(where: {
                  $0.kind == .recoverCanceledCheckout(request.destinationPath)
              }) else { return }
        let operationID = beginOperation(.recoverCanceledCheckout(request.destinationPath))
        defer { endOperation(operationID) }
        do {
            try await client.validateWorkingCopy(
                at: request.destinationPath,
                credentials: pendingCheckoutCredentials(for: request)
            )
            try workingCopyRecoveryFileManager.emptyWorkingCopy(at: request.destinationPath)
            sessionPasswords[request.id] = nil
            projectAccessManager.endAccessing(projectID: request.id)
            canceledCheckoutRecoveryRequest = nil
            notice = AppLanguage.current.localized(
                "ui.canceled.checkout.folder.emptied.b08f7c21",
                request.destinationPath
            )
        } catch {
            errorMessage = AppLanguage.current.localized(
                "ui.canceled.checkout.folder.not.emptied.9ea1354b",
                request.destinationPath,
                SVNErrorLocalization.diagnosticDetails(for: error)
            )
        }
    }

    func dismissCanceledCheckoutRecovery(_ request: CanceledCheckoutRecoveryRequest) {
        guard canceledCheckoutRecoveryRequest?.id == request.id else { return }
        sessionPasswords[request.id] = nil
        projectAccessManager.endAccessing(projectID: request.id)
        canceledCheckoutRecoveryRequest = nil
        notice = AppLanguage.current.localized(
            "ui.the.checkout.was.canceled.partially.downloaded.f.7a1c4d58",
            request.destinationPath
        )
    }

    private func pendingCheckoutCredentials(
        for request: CanceledCheckoutRecoveryRequest
    ) -> SVNCredentials? {
        guard let username = request.username else { return nil }
        return SVNCredentials(username: username, password: sessionPasswords[request.id])
    }
}
