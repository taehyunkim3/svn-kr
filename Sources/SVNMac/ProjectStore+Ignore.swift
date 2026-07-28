import Foundation
import SVNCore

extension ProjectStore {
    func setShowsIgnoredFiles(_ showsIgnoredFiles: Bool) async {
        self.showsIgnoredFiles = showsIgnoredFiles
        guard showsIgnoredFiles, let project = selectedProject else {
            ignoredStatuses = []
            return
        }
        do { ignoredStatuses = try await client.ignoredStatus(at: project.path, credentials: nil) }
        catch { errorMessage = localizedError(error) }
    }

    func loadIgnoreRules() async {
        guard let project = selectedProject else { return }
        do { ignoreRules = try await client.ignoreRules(at: project.path, credentials: nil) }
        catch { errorMessage = localizedError(error) }
    }

    func ignore(path relativePath: String, byExtension: Bool) async {
        guard let project = selectedProject else { return }
        let path = relativePath as NSString
        let directory = path.deletingLastPathComponent.isEmpty ? "." : path.deletingLastPathComponent
        let pattern = byExtension && !path.pathExtension.isEmpty ? "*.\(path.pathExtension)" : path.lastPathComponent
        let operationID = beginOperation(.ignore(project.id))
        defer { endOperation(operationID) }
        do {
            try await client.addIgnoreRule(
                at: project.path,
                directory: directory,
                pattern: pattern,
                propertyKind: .local,
                credentials: nil
            )
            notice = AppLanguage.current.text("무시 규칙 '\(pattern)'을 추가했습니다. 디렉터리 속성을 커밋하면 팀에 공유됩니다.", "Added ignore rule '\(pattern)'. Commit the directory property to share it with the team.")
            await refresh()
            await loadIgnoreRules()
        } catch { errorMessage = localizedError(error) }
    }

    func removeIgnoreRule(_ rule: SVNIgnoreRule) async {
        guard let project = selectedProject else { return }
        guard rule.inheritedFrom == nil else {
            errorMessage = AppLanguage.current.text(
                "상속된 규칙은 속성을 설정한 상위 디렉터리에서만 제거할 수 있습니다.",
                "Inherited rules can only be removed from the parent directory that owns the property."
            )
            return
        }
        let operationID = beginOperation(.ignore(project.id))
        defer { endOperation(operationID) }
        do {
            try await client.removeIgnoreRule(
                at: project.path,
                directory: rule.directory,
                pattern: rule.pattern,
                propertyKind: rule.propertyKind,
                credentials: nil
            )
            notice = AppLanguage.current.text("무시 규칙 '\(rule.pattern)'을 제거했습니다.", "Removed ignore rule '\(rule.pattern)'.")
            await refresh()
            await loadIgnoreRules()
            if showsIgnoredFiles { await setShowsIgnoredFiles(true) }
        } catch { errorMessage = localizedError(error) }
    }
}
