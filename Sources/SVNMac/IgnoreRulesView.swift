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
                Text(appLanguage.localized(.ui.manage.ignoreRules)).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized(.ui.close.label)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List {
                Section(appLanguage.localized(.ui.svn.ignoreRules)) {
                    if store.ignoreRules.isEmpty {
                        Text(appLanguage.localized(.ui.no.svnIgnoreRulesAreConfigured))
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
                                appLanguage.localized(.ui.no.gitignore),
                                systemImage: "doc.badge.questionmark",
                                description: Text(appLanguage.localized(.ui.no.gitignoreFileWasFoundInTheWorkingCopy))
                            )
                        } else if store.gitIgnoreImportItems.isEmpty {
                            Text(appLanguage.localized(.ui.there.areNoGitRulesToImport))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.gitIgnoreImportItems) { item in
                                gitImportRow(item)
                            }
                        }
                    }
                } header: {
                    Text(appLanguage.localized(.ui.localizationImport.gitRules))
                } footer: {
                    Text(appLanguage.localized(.ui.gitignore.isNotModifiedImportIsOneWayAnd))
                }
            }

            Divider()
            HStack {
                Text(appLanguage.localized(.ui.already.versionedFilesAreNotHiddenByIgnore))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.requestApplyGitIgnoreSelection()
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.apply.selectedRules),
                        inProgressTitle: appLanguage.localized(.ui.applying.label),
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
            appLanguage.localized(.ui.apply.globalIgnoreRules),
            isPresented: $store.requiresGlobalIgnoreImportConfirmation
        ) {
            Button(appLanguage.localized(.ui.apply.label), role: .destructive) {
                Task { await store.applySelectedGitIgnoreRules() }
            }
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                store.requiresGlobalIgnoreImportConfirmation = false
            }
        } message: {
            Text(appLanguage.localized(.ui.global.rulesCanAffectManyDirectoriesBelowT))
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
                        Text(appLanguage.localized(.ui.inherited.from, inheritedFrom))
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
                    title: appLanguage.localized(.ui.remove.label),
                    systemImage: "trash",
                    isInProgress: store.isIgnoringSelectedProject
                )
            }
            .disabled(store.isSelectedProjectActionBlocked || rule.inheritedFrom != nil)
            .help(rule.inheritedFrom == nil
                ? appLanguage.localized(.ui.remove.thisRule)
                : appLanguage.localized(.ui.remove.inheritedRulesFromTheParentDirectory))
        }
    }

    private var gitImportControls: some View {
        HStack {
            Button {
                Task { await store.compareGitIgnore() }
            } label: {
                ActionProgressLabel(
                    title: appLanguage.localized(.ui.compare.gitRules),
                    systemImage: "arrow.triangle.2.circlepath",
                    isInProgress: store.isIgnoringSelectedProject
                )
            }
            .disabled(store.isSelectedProjectActionBlocked)
            if let comparedAt = store.gitIgnoreLastComparedAt {
                Text(appLanguage.localized(.ui.last.compared, comparedAt.formatted(date: .omitted, time: .shortened)))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.gitIgnoreFileExists {
                Button(appLanguage.localized(.ui.select.allSelectAll)) {
                    store.selectedGitIgnoreImportIDs = store.selectableGitIgnoreImportIDs
                }
                Button(appLanguage.localized(.ui.clear.label)) {
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
        case .alreadyApplied: appLanguage.localized(.ui.applied.label)
        case let .proposal(_, requiresConfirmation):
            requiresConfirmation
                ? appLanguage.localized(.ui.review.label)
                : appLanguage.localized(.ui.available.label)
        case .unsupported: appLanguage.localized(.ui.unsupported.label)
        case .conflict: appLanguage.localized(.ui.conflict.label)
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
