import SwiftUI
import SVNCore

/// 선택한 서버 리비전의 실제 패치를 기록 목록과 분리해 표시합니다.
/// 바이너리 변경처럼 SVN이 텍스트 패치를 만들 수 없는 경우도 의미 있는 상태로 안내합니다.
struct HistoryRevisionDiffView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let revision = store.selectedHistoryRevision {
                    Label("r\(revision)", systemImage: "doc.text.magnifyingglass")
                        .font(.headline.monospacedDigit())
                } else {
                    Label(appLanguage.localized(.ui.commit.changes), systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
            Divider()

            stableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .historyRevisionRestoreConfirmation()
    }

    /// 선택/로딩 상태가 바뀌어도 파일 목록과 diff 컨테이너 자체는 교체하지 않습니다.
    /// 컨테이너 타입을 유지해야 List와 placeholder의 고유 크기 차이로 패널이 재배치되지 않습니다.
    private var stableContent: some View {
        VStack(spacing: 0) {
            changedPathList(selectedEntry?.changedPaths ?? [])
                .frame(height: AppLayout.historyChangedFilesHeight)

            Divider()

            if let context = selectedRevisionActionContext {
                HistoryRevisionActions(
                    fileHistoryRequest: context.fileHistoryRequest,
                    revision: context.contentRevision
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            }

            selectedPathDiff
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(selectedEntry == nil ? 0 : 1)
        .overlay {
            if store.logs.isEmpty, store.isHistoryLoading {
                ProgressView(appLanguage.localized(.ui.loading.commitHistory))
            } else if store.selectedHistoryRevision == nil {
                ContentUnavailableView(
                    appLanguage.localized(.ui.select.aCommit),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(appLanguage.localized(.ui.choose.viewChangesInTheHistoryToDisplayTh))
                )
            } else if selectedEntry == nil {
                ContentUnavailableView(
                    appLanguage.localized(.ui.commit.notFound),
                    systemImage: "exclamationmark.magnifyingglass"
                )
            }
        }
    }

    private func changedPathList(_ paths: [SVNChangedPath]) -> some View {
        let files = paths.filter { changedPath in
            if case .directory? = changedPath.kind { return false }
            return true
        }
        return List(files) { changedPath in
                let presentation = HistoryPathPresentation(
                    repositoryPath: changedPath.path,
                    workingCopyRepositoryPath: store.workingCopyRepositoryPath
                )
                Button {
                    guard let revision = store.selectedHistoryRevision else { return }
                    store.prepareHistoryRevisionActions(
                        revision: revision,
                        changedPath: changedPath
                    )
                    Task { await store.loadHistoryDiff(for: revision, changedPath: changedPath) }
                } label: {
                    HStack(spacing: 8) {
                        Text(changedPath.action.rawValue)
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(actionColor(changedPath.action))
                            .frame(width: 18)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(presentation.fileName)
                                .font(.caption.monospaced().weight(.medium))
                            if !presentation.directory.isEmpty {
                                Text(presentation.directory)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    store.selectedHistoryPath == changedPath.path
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear
                )
                .help(presentation.relativePath)
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView(
                    appLanguage.localized(.ui.no.changedFiles),
                    systemImage: "doc"
                )
            }
        }
    }

    @ViewBuilder
    private var selectedPathDiff: some View {
        if store.selectedHistoryPath == nil {
            ContentUnavailableView(
                appLanguage.localized(.ui.select.aFile),
                systemImage: "doc.text.magnifyingglass",
                description: Text(appLanguage.localized(.ui.choose.aChangedFileAboveToDisplayOnlyThat))
            )
        } else if isLoading {
            VStack {
                Spacer()
                ProgressView(appLanguage.localized(.ui.loading.changes))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if case let .text(value) = store.historyDiffContent {
            diffText(value)
        } else if case let .failure(message) = store.historyDiffContent {
            ContentUnavailableView(
                appLanguage.localized(.ui.unable.toLoadChanges),
                systemImage: "lock.trianglebadge.exclamationmark",
                description: Text(historyDiffFailureDescription(message))
            )
        } else {
            Text(store.historyDiffContent.localizedText(appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func historyDiffFailureDescription(_ message: String) -> String {
        if message.contains("E175013") || message.localizedCaseInsensitiveContains("forbidden") {
            return appLanguage.localized(.ui.the.svnServerDeniedReadAccessToThisFileC, message)
        }
        return message
    }

    private func diffText(_ value: String) -> some View {
        DiffTextView(value)
    }

    private var selectedEntry: SVNLogEntry? {
        guard let revision = store.selectedHistoryRevision else { return nil }
        return store.logs.first { $0.revision == revision }
    }

    private var selectedRevisionActionContext: HistoryRevisionActionContext? {
        guard let context = store.recoveryState.historyRevisionActionContext,
              context.selectedRevision == store.selectedHistoryRevision,
              context.repositoryPath == store.selectedHistoryPath else { return nil }
        return context
    }

    private func actionColor(_ action: SVNChangeAction) -> Color {
        action.presentationColor
    }

    private var isLoading: Bool {
        guard let projectID = store.selectedProjectID else { return false }
        return store.activeOperations.contains { $0.kind == .revisionDiff(projectID) }
    }
}
