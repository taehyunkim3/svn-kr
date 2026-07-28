import SwiftUI
import SVNCore

/// 작업 복사본에 설정된 `svn:ignore` 속성을 한곳에서 확인하고 제거합니다.
/// 규칙 추가는 실제 미추적 파일의 컨텍스트 메뉴에서 수행해 잘못된 경로 입력을 피합니다.
struct IgnoreRulesView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.text("SVN 무시 규칙", "SVN Ignore Rules")).font(.title2.bold())
                Spacer()
                Button(appLanguage.text("닫기", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            List(store.ignoreRules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
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
            .overlay {
                if store.ignoreRules.isEmpty {
                    ContentUnavailableView(
                        appLanguage.text("무시 규칙 없음", "No Ignore Rules"),
                        systemImage: "eye.slash",
                        description: Text(appLanguage.text("변경 목록의 미추적 파일을 우클릭해 규칙을 추가할 수 있습니다.", "Right-click an unversioned item in Changes to add a rule."))
                    )
                }
            }

            Divider()
            Text(appLanguage.text(
                "규칙 변경은 해당 디렉터리의 SVN 속성 변경으로 표시됩니다. 그 변경을 커밋해야 다른 사용자에게도 공유됩니다.",
                "Rule changes appear as SVN property changes on the directory. Commit that change to share it with others."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.ignoreRulesSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }
}
