import Foundation
import SVNCore

extension ProjectStore {
    var selectableGitIgnoreImportIDs: Set<IgnoreImportItem.ID> {
        Set(gitIgnoreImportItems.lazy.filter(\.isSelectable).map(\.id))
    }

    func setShowsIgnoredFiles(_ showsIgnoredFiles: Bool) async {
        self.showsIgnoredFiles = showsIgnoredFiles
        guard showsIgnoredFiles, let project = selectedProject else {
            ignoredStatuses = []
            return
        }
        do {
            let statuses = try await client.ignoredStatus(at: project.path, credentials: nil)
            guard selectedProjectID == project.id else { return }
            ignoredStatuses = statuses
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }

    func loadIgnoreRules() async {
        guard let project = selectedProject else { return }
        do {
            let rules = try await client.ignoreRules(at: project.path, credentials: nil)
            guard selectedProjectID == project.id else { return }
            ignoreRules = rules
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
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
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized(.ui.ignore.addedIgnoreRuleCommitDirectoryPropertyShareItTeam, pattern)
            await refresh()
            await loadIgnoreRules()
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }

    func removeIgnoreRule(_ rule: SVNIgnoreRule) async {
        guard let project = selectedProject else { return }
        guard rule.inheritedFrom == nil else {
            errorMessage = AppLanguage.current.localized(.ui.ignore.inheritedRulesCanOnlyRemovedParentDirectoryThatOwnsProperty)
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
            guard selectedProjectID == project.id else { return }
            notice = AppLanguage.current.localized(.ui.ignore.removedIgnoreRule, rule.pattern)
            await refresh()
            await loadIgnoreRules()
            if showsIgnoredFiles { await setShowsIgnoredFiles(true) }
        } catch {
            guard selectedProjectID == project.id else { return }
            errorMessage = localizedError(error)
        }
    }

    func compareGitIgnore() async {
        guard let project = selectedProject else { return }
        guard pathCollisions.isEmpty else {
            errorMessage = AppLanguage.current.localized(.ui.ignore.resolveUnicodePathConflictsBeforeComparingGitRulesSoProperty)
            return
        }
        let projectRoot = URL(fileURLWithPath: project.path, isDirectory: true)
        hasComparedGitIgnore = true
        gitIgnoreLastComparedAt = Date()

        let operationID = beginOperation(.ignore(project.id))
        defer { endOperation(operationID) }
        do {
            async let entriesRequest = client.workingCopyEntries(at: project.path, credentials: nil)
            async let rulesRequest = client.ignoreRules(at: project.path, credentials: nil)
            let (entries, rules) = try await (entriesRequest, rulesRequest)
            guard selectedProjectID == project.id else { return }

            var managedDirectories: Set<String> = ["."]
            var versionedDirectories: [String] = ["."]
            for entry in entries where entry.isVersioned {
                var isDirectory: ObjCBool = false
                let absolutePath = projectRoot.appendingPathComponent(entry.path).path
                if FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    managedDirectories.insert(entry.path)
                    versionedDirectories.append(entry.path)
                }
            }

            var allRules: [GitIgnoreRule] = []
            var foundAnyGitIgnoreFile = false
            for directory in versionedDirectories {
                let gitIgnoreURL = (directory == "." ? projectRoot : projectRoot.appendingPathComponent(directory, isDirectory: true))
                    .appendingPathComponent(".gitignore", isDirectory: false)
                guard FileManager.default.fileExists(atPath: gitIgnoreURL.path) else { continue }
                foundAnyGitIgnoreFile = true
                let contents = try String(contentsOf: gitIgnoreURL, encoding: .utf8)
                allRules.append(contentsOf: GitIgnoreParser.parse(contents, sourceDirectory: directory))
            }
            guard selectedProjectID == project.id else { return }

            guard foundAnyGitIgnoreFile else {
                gitIgnoreFileExists = false
                gitIgnoreImportItems = []
                selectedGitIgnoreImportIDs = []
                return
            }

            gitIgnoreFileExists = true
            ignoreRules = rules
            gitIgnoreImportItems = GitIgnoreImporter.makePreview(
                rules: allRules,
                existingRules: rules,
                managedDirectories: managedDirectories,
                trackedPaths: entries.filter(\.isVersioned).map(\.path)
            )
            selectedGitIgnoreImportIDs = Set(
                gitIgnoreImportItems.lazy.filter { item in
                    guard case let .proposal(_, requiresConfirmation) = item.disposition else { return false }
                    return !requiresConfirmation
                }.map(\.id)
            )
        } catch {
            if selectedProjectID == project.id {
                errorMessage = localizedError(error)
            }
        }
    }

    func requestApplyGitIgnoreSelection() {
        let selectedItems = gitIgnoreImportItems.filter {
            selectedGitIgnoreImportIDs.contains($0.id)
        }
        if selectedItems.contains(where: {
            if case let .proposal(_, requiresConfirmation) = $0.disposition {
                return requiresConfirmation
            }
            return false
        }) {
            requiresGlobalIgnoreImportConfirmation = true
        } else {
            Task { await applySelectedGitIgnoreRules() }
        }
    }

    func applySelectedGitIgnoreRules() async {
        guard let project = selectedProject else { return }
        requiresGlobalIgnoreImportConfirmation = false
        let proposals = gitIgnoreImportItems.compactMap { item -> SVNIgnoreRule? in
            guard selectedGitIgnoreImportIDs.contains(item.id) else { return nil }
            return item.proposal
        }
        guard !proposals.isEmpty else { return }

        let operationID = beginOperation(.ignore(project.id))
        defer { endOperation(operationID) }
        var applicationError: Error?
        for proposal in proposals {
            do {
                try await client.addIgnoreRule(
                    at: project.path,
                    directory: proposal.directory,
                    pattern: proposal.pattern,
                    propertyKind: proposal.propertyKind,
                    credentials: nil
                )
                guard selectedProjectID == project.id else { return }
            } catch {
                applicationError = error
                break
            }
        }
        guard selectedProjectID == project.id else { return }
        await refreshLocalWorkingCopy()
        guard selectedProjectID == project.id else { return }
        await compareGitIgnore()
        guard selectedProjectID == project.id else { return }
        if showsIgnoredFiles { await setShowsIgnoredFiles(true) }

        if let applicationError {
            errorMessage = localizedError(applicationError)
        } else {
            notice = AppLanguage.current.localized(.ui.ignore.appliedGitRuleSvnIgnorePropertiesCommitPropertyChangesShare, proposals.count)
        }
    }
}
