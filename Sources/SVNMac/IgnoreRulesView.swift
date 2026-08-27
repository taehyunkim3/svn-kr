import SwiftUI
import SVNCore

struct IgnoreRulesView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.localized(.ui.ignore.manageIgnoreRules)).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized(.ui.common.close)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List {
                Section(appLanguage.localized(.ui.ignore.svnIgnoreRules)) {
                    if store.ignoreRules.isEmpty {
                        Text(appLanguage.localized(.ui.ignore.noSvnIgnoreRulesConfigured))
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.ignoreRules) { rule in
                            svnRuleRow(rule)
                        }
                    }
                }

                Section {
                    gitImportControls
                    if store.hasComparedGitIgnore {
                        if !store.gitIgnoreFileExists {
                            ContentUnavailableView(
                                appLanguage.localized(.ui.ignore.noGitignore),
                                systemImage: "doc.badge.questionmark",
                                description: Text(appLanguage.localized(.ui.ignore.noGitignoreFileFoundWorkingCopy))
                            )
                        } else if store.gitIgnoreImportItems.isEmpty {
                            Text(appLanguage.localized(.ui.ignore.thereNoGitRulesImport))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.gitIgnoreImportItems) { item in
                                gitImportRow(item)
                            }
                        }
                    }
                } header: {
                    Text(appLanguage.localized(.ui.ignore.importGitRules))
                } footer: {
                    Text(appLanguage.localized(.ui.ignore.gitignoreNotModifiedImportOneWaySvnPropertyChangesMust))
                }
            }

            Divider()
            HStack {
                Text(appLanguage.localized(.ui.ignore.alreadyVersionedFilesNotHiddenIgnoreRules))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.requestApplyGitIgnoreSelection()
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.ignore.applySelectedRules),
                        inProgressTitle: appLanguage.localized(.ui.ignore.applying),
                        isInProgress: store.isIgnoringSelectedProject
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.selectedGitIgnoreImportIDs.isEmpty
                        || store.isSelectedProjectActionBlocked
                )
            }
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.ignoreRulesSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
        .alert(
            appLanguage.localized(.ui.ignore.applyGlobalIgnoreRules),
            isPresented: $store.requiresGlobalIgnoreImportConfirmation
        ) {
            Button(appLanguage.localized(.ui.ignore.apply), role: .destructive) {
                Task { await store.applySelectedGitIgnoreRules() }
            }
            Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                store.requiresGlobalIgnoreImportConfirmation = false
            }
        } message: {
            Text(appLanguage.localized(.ui.ignore.globalRulesCanAffectManyDirectoriesBelowWorkingCopyApply))
        }
    }

    private func svnRuleRow(_ rule: SVNIgnoreRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.pattern).font(.body.monospaced())
                HStack(spacing: 6) {
                    StatusBadge(
                        label: rule.propertyKind == .local ? "svn:ignore" : "svn:global-ignores",
                        color: .secondary,
                        style: .tinted,
                        verticalPadding: 2
                    )
                    Text(rule.directory).font(.caption.monospaced())
                    if let inheritedFrom = rule.inheritedFrom {
                        Text(appLanguage.localized(.ui.ignore.inherited, inheritedFrom))
                        .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await store.removeIgnoreRule(rule) }
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized(.ui.common.remove),
                    systemImage: "trash",
                    isInProgress: store.isIgnoringSelectedProject
                )
            }
            .disabled(store.isSelectedProjectActionBlocked || rule.inheritedFrom != nil)
            .help(rule.inheritedFrom == nil
                ? appLanguage.localized(.ui.ignore.removeRule)
                : appLanguage.localized(.ui.ignore.removeInheritedRulesParentDirectoryThatOwnsProperty))
        }
    }

    private var gitImportControls: some View {
        HStack {
            Button {
                Task { await store.compareGitIgnore() }
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized(.ui.ignore.compareGitRules),
                    systemImage: "arrow.triangle.2.circlepath",
                    isInProgress: store.isIgnoringSelectedProject
                )
            }
            .disabled(store.isSelectedProjectActionBlocked)
            if let comparedAt = store.gitIgnoreLastComparedAt {
                Text(appLanguage.localized(.ui.ignore.lastCompared, comparedAt.formatted(date: .omitted, time: .shortened)))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.gitIgnoreFileExists {
                Button(appLanguage.localized(.ui.ignore.selectAll)) {
                    store.selectedGitIgnoreImportIDs = store.selectableGitIgnoreImportIDs
                }
                Button(appLanguage.localized(.ui.ignore.clear)) {
                    store.selectedGitIgnoreImportIDs.removeAll()
                }
            }
        }
    }

    private func gitImportRow(_ item: IgnoreImportItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { store.selectedGitIgnoreImportIDs.contains(item.id) },
                set: { selected in
                    if selected { store.selectedGitIgnoreImportIDs.insert(item.id) }
                    else { store.selectedGitIgnoreImportIDs.remove(item.id) }
                }
            ))
            .labelsHidden()
            .disabled(!item.isSelectable)
            .iconHelp(appLanguage.localized(.ui.ignore.includeRule, item.rule.rawPattern))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.rule.rawPattern).font(.body.monospaced())
                    Text(importStatus(item))
                        .font(.caption2.bold())
                        .foregroundStyle(importStatusColor(item))
                }
                Text(gitIgnoreSourcePath(item.rule))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                if let proposal = item.proposal {
                    Text("\(proposal.propertyKind.propertyName) · \(proposal.directory) · \(proposal.pattern)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else if let reason = importReason(item) {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if let warning = item.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func importStatus(_ item: IgnoreImportItem) -> String {
        switch item.disposition {
        case .alreadyApplied: appLanguage.localized(.ui.ignore.applied)
        case let .proposal(_, requiresConfirmation):
            requiresConfirmation
                ? appLanguage.localized(.ui.ignore.review)
                : appLanguage.localized(.ui.ignore.available)
        case .unsupported: appLanguage.localized(.ui.ignore.unsupported)
        case .conflict: appLanguage.localized(.ui.conflict.conflict)
        }
    }

    private func importStatusColor(_ item: IgnoreImportItem) -> Color {
        switch item.disposition {
        case .alreadyApplied: .secondary
        case let .proposal(_, requiresConfirmation): requiresConfirmation ? .orange : .green
        case .unsupported: .secondary
        case .conflict: .red
        }
    }

    private func importReason(_ item: IgnoreImportItem) -> String? {
        switch item.disposition {
        case let .unsupported(reason), let .conflict(reason): reason
        default: nil
        }
    }

    private func gitIgnoreSourcePath(_ rule: GitIgnoreRule) -> String {
        rule.sourceDirectory == "." ? ".gitignore" : "\(rule.sourceDirectory)/.gitignore"
    }
}
