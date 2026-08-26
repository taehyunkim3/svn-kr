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
            errorMessage = AppLanguage.current.localized(.ui.recovery.localWorkingFolderAlreadyRegistered)
            return false
        }
        // 폴더 선택 창은 현재 작업 폴더에서 열리므로 그 안에 새 폴더를 만들기 쉽습니다.
        // 그대로 두면 새 체크아웃이 원본의 미등록 항목으로 잡혀 저장소 전체가 중첩 복사됩니다.
        guard Self.recoveryDestinationIsOutside(sourcePath: sourceProject.path, destination: destination) else {
            errorMessage = AppLanguage.current.localized(
                .ui.recovery.recoveryFolderMustBeOutsideCurrentWorkingFolder
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
                allowsUntrustedServerCertificate: sourceProject.allowsUntrustedServerCertificate == true,
                // 세부 허용값까지 옮기지 않으면 복구 직후 새로고침부터 같은 인증서를
                // 다시 거부하거나 승인 화면을 또 띄웁니다.
                allowedServerCertificateFailures: allowedServerCertificateFailures(for: sourceProject)
            )
            let recoveryIsStillCurrent = selectedProjectID == sourceID
                && pathRecoverySourceProjectID == sourceID
            if recoveryIsStillCurrent {
                registerRecoveredCheckout(recoveredProject)
            } else {
                projects.append(recoveredProject)
            }

            if let password = sourceCredentials?.password, !password.isEmpty {
                sessionPasswords[recoveredID] = password
                try? credentialStore.setPassword(password, for: recoveredID)
            }

            guard recoveryIsStillCurrent else { return true }
            await refresh()
            guard selectedProjectID == recoveredID else { return true }
            notice = AppLanguage.current.localized(.ui.recovery.pathRecoveryCompletedOriginalWorkingFolderPreserved)
            return true
        } catch {
            projectAccessManager.endAccessing(projectID: recoveredID)
            errorMessage = localizedError(error)
            return false
        }
    }

    /// APFS는 대소문자와 유니코드 정규화를 무시하므로 포함 관계 판정도 같은 기준으로 접습니다.
    static func recoveryDestinationIsOutside(sourcePath: String, destination: URL) -> Bool {
        let source = comparableRecoveryPath(URL(fileURLWithPath: sourcePath, isDirectory: true))
        let target = comparableRecoveryPath(destination)
        return source != target
            && !target.hasPrefix(source + "/")
            && !source.hasPrefix(target + "/")
    }

    private static func comparableRecoveryPath(_ url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}
