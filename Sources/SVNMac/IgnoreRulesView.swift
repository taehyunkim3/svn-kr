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
                Text(appLanguage.localized("ui.manage.ignore.rules.7eac76b1")).font(.title2.bold())
                Spacer()
                Button(appLanguage.localized("ui.close.3ea43db3")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List {
                Section(appLanguage.localized("ui.svn.ignore.rules.90435aad")) {
                    if store.ignoreRules.isEmpty {
                        Text(appLanguage.localized("ui.no.svn.ignore.rules.are.configured.71e0180f"))
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
                                appLanguage.localized("ui.no.gitignore.44540a9b"),
                                systemImage: "doc.badge.questionmark",
                                description: Text(appLanguage.localized("ui.no.gitignore.file.was.found.in.the.working.copy.ce93a706"))
                            )
                        } else if store.gitIgnoreImportItems.isEmpty {
                            Text(appLanguage.localized("ui.there.are.no.git.rules.to.import.03bd12e9"))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.gitIgnoreImportItems) { item in
                                gitImportRow(item)
                            }
                        }
                    }
                } header: {
                    Text(appLanguage.localized("ui.import.git.rules.bbf8aa32"))
                } footer: {
                    Text(appLanguage.localized("ui.gitignore.is.not.modified.import.is.one.way.and..544de7a7"))
                }
            }

            Divider()
            HStack {
                Text(appLanguage.localized("ui.already.versioned.files.are.not.hidden.by.ignore.ed1d7db7"))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.localized("ui.apply.selected.rules.f6bb01fa")) {
                    store.requestApplyGitIgnoreSelection()
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
            appLanguage.localized("ui.apply.global.ignore.rules.1ece4ab2"),
            isPresented: $store.requiresGlobalIgnoreImportConfirmation
        ) {
            Button(appLanguage.localized("ui.apply.aa6f48d5"), role: .destructive) {
                Task { await store.applySelectedGitIgnoreRules() }
            }
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
                store.requiresGlobalIgnoreImportConfirmation = false
            }
        } message: {
            Text(appLanguage.localized("ui.global.rules.can.affect.many.directories.below.t.164333fd"))
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
                        Text(appLanguage.localized("ui.inherited.from.1feb128b", inheritedFrom))
                        .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await store.removeIgnoreRule(rule) }
            } label: {
                Label(appLanguage.localized("ui.remove.d4be5a3e"), systemImage: "trash")
            }
            .disabled(store.isSelectedProjectActionBlocked || rule.inheritedFrom != nil)
            .help(rule.inheritedFrom == nil
                ? appLanguage.localized("ui.remove.this.rule.2908b9d1")
                : appLanguage.localized("ui.remove.inherited.rules.from.the.parent.directory.7c2d3995"))
        }
    }

    private var gitImportControls: some View {
        HStack {
            Button(appLanguage.localized("ui.compare.git.rules.2220d6b1"), systemImage: "arrow.triangle.2.circlepath") {
                Task { await store.compareGitIgnore() }
            }
            .disabled(store.isSelectedProjectActionBlocked)
            if let comparedAt = store.gitIgnoreLastComparedAt {
                Text(appLanguage.localized("ui.last.compared.cbf0bf20", comparedAt.formatted(date: .omitted, time: .shortened)))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.gitIgnoreFileExists {
                Button(appLanguage.localized("ui.select.all.061b129c")) {
                    store.selectedGitIgnoreImportIDs = store.selectableGitIgnoreImportIDs
                }
                Button(appLanguage.localized("ui.clear.8cfe548b")) {
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
        case .alreadyApplied: appLanguage.localized("ui.applied.faddeb33")
        case let .proposal(_, requiresConfirmation):
            requiresConfirmation
                ? appLanguage.localized("ui.review.618262db")
                : appLanguage.localized("ui.available.cb60f347")
        case .unsupported: appLanguage.localized("ui.unsupported.3d400c13")
        case .conflict: appLanguage.localized("ui.conflict.37edb628")
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
