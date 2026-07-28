import SwiftUI
import SVNCore

struct IgnoreRulesView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.text("무시 규칙 관리", "Manage Ignore Rules")).font(.title2.bold())
                Spacer()
                Button(appLanguage.text("닫기", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List {
                Section(appLanguage.text("SVN 무시 규칙", "SVN Ignore Rules")) {
                    if store.ignoreRules.isEmpty {
                        Text(appLanguage.text(
                            "설정된 SVN 무시 규칙이 없습니다.",
                            "No SVN ignore rules are configured."
                        ))
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
                                appLanguage.text(".gitignore 없음", "No .gitignore"),
                                systemImage: "doc.badge.questionmark",
                                description: Text(appLanguage.text(
                                    "작업 복사본 루트에서 .gitignore 파일을 찾지 못했습니다.",
                                    "No .gitignore file was found at the working-copy root."
                                ))
                            )
                        } else if store.gitIgnoreImportItems.isEmpty {
                            Text(appLanguage.text(
                                "가져올 Git 규칙이 없습니다.",
                                "There are no Git rules to import."
                            ))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.gitIgnoreImportItems) { item in
                                gitImportRow(item)
                            }
                        }
                    }
                } header: {
                    Text(appLanguage.text("Git 규칙 가져오기", "Import Git Rules"))
                } footer: {
                    Text(appLanguage.text(
                        ".gitignore는 변경하지 않습니다. 가져오기는 단방향이며 SVN 속성 변경을 커밋해야 팀에 공유됩니다.",
                        ".gitignore is not modified. Import is one-way, and SVN property changes must be committed to share them."
                    ))
                }
            }

            Divider()
            HStack {
                Text(appLanguage.text(
                    "이미 추적 중인 파일은 무시 규칙으로 숨겨지지 않습니다.",
                    "Already versioned files are not hidden by ignore rules."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(appLanguage.text("선택 규칙 적용", "Apply Selected Rules")) {
                    store.requestApplyGitIgnoreSelection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.selectedGitIgnoreImportIDs.isEmpty
                        || store.isWorking
                )
            }
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.ignoreRulesSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
        .alert(
            appLanguage.text("전역 무시 규칙을 적용할까요?", "Apply Global Ignore Rules?"),
            isPresented: $store.requiresGlobalIgnoreImportConfirmation
        ) {
            Button(appLanguage.text("적용", "Apply"), role: .destructive) {
                Task { await store.applySelectedGitIgnoreRules() }
            }
            Button(appLanguage.text("취소", "Cancel"), role: .cancel) {
                store.requiresGlobalIgnoreImportConfirmation = false
            }
        } message: {
            Text(appLanguage.text(
                "전역 규칙은 작업 복사본 아래의 여러 디렉터리에 영향을 줄 수 있습니다. 선택한 범위를 확인한 경우에만 적용하세요.",
                "Global rules can affect many directories below the working copy. Apply only after reviewing the scope."
            ))
        }
    }

    private func svnRuleRow(_ rule: SVNIgnoreRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.pattern).font(.body.monospaced())
                HStack(spacing: 6) {
                    Text(rule.propertyKind == .local ? "svn:ignore" : "svn:global-ignores")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                    Text(rule.directory).font(.caption.monospaced())
                    if let inheritedFrom = rule.inheritedFrom {
                        Text(appLanguage.text(
                            "\(inheritedFrom)에서 상속",
                            "Inherited from \(inheritedFrom)"
                        ))
                        .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await store.removeIgnoreRule(rule) }
            } label: {
                Label(appLanguage.text("제거", "Remove"), systemImage: "trash")
            }
            .disabled(store.isWorking || rule.inheritedFrom != nil)
            .help(rule.inheritedFrom == nil
                ? appLanguage.text("이 규칙을 제거합니다.", "Remove this rule.")
                : appLanguage.text(
                    "상속된 규칙은 속성을 설정한 상위 디렉터리에서 제거해야 합니다.",
                    "Remove inherited rules from the parent directory that owns the property."
                ))
        }
    }

    private var gitImportControls: some View {
        HStack {
            Button(appLanguage.text("Git 규칙과 비교", "Compare Git Rules"), systemImage: "arrow.triangle.2.circlepath") {
                Task { await store.compareGitIgnore() }
            }
            .disabled(store.isWorking)
            if let comparedAt = store.gitIgnoreLastComparedAt {
                Text(appLanguage.text(
                    "마지막 비교 \(comparedAt.formatted(date: .omitted, time: .shortened))",
                    "Last compared \(comparedAt.formatted(date: .omitted, time: .shortened))"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.gitIgnoreFileExists {
                Button(appLanguage.text("모두 선택", "Select All")) {
                    store.selectedGitIgnoreImportIDs = store.selectableGitIgnoreImportIDs
                }
                Button(appLanguage.text("선택 해제", "Clear")) {
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
        case .alreadyApplied: appLanguage.text("이미 적용", "Applied")
        case let .proposal(_, requiresConfirmation):
            requiresConfirmation
                ? appLanguage.text("확인 필요", "Review")
                : appLanguage.text("추가 가능", "Available")
        case .unsupported: appLanguage.text("변환 불가", "Unsupported")
        case .conflict: appLanguage.text("충돌", "Conflict")
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
}
