import SwiftUI

/// 커밋 메시지 입력 갱신을 대용량 변경 파일 목록과 분리합니다.
struct CommitControlsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @State private var commitMessage = ""
    @FocusState private var isCommitMessageFocused: Bool

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 8) {
            TextField(appLanguage.localized(.ui.commit.message), text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .focused($isCommitMessageFocused)
                .onSubmit { submitCommitAfterEndingTextInput() }
            HStack {
                Button(appLanguage.localized(.ui.select.allSelectAll2)) {
                    store.selectedPaths = store.selectAllStatusPaths
                }
                .help(appLanguage.localized(.ui.select.allCurrentlyChangedFilesForCommit))
                Button(appLanguage.localized(.ui.clear.selection)) { store.selectedPaths.removeAll() }
                    .help(appLanguage.localized(.ui.clear.allSelectedCommitTargets))
                Spacer()
                Text(appLanguage.localized(.ui.selected.label, store.selectedPaths.count))
                    .foregroundStyle(.secondary)
                if store.scheduledDeletionCount > 0 {
                    Text(appLanguage.localized(.ui.pending.deletionFormatted, store.scheduledDeletionCount))
                    .foregroundStyle(.red)
                }
                Button(action: submitCommitAfterEndingTextInput) {
                    HStack(spacing: 6) {
                        if store.isCommittingSelectedProject {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.isCommittingSelectedProject
                            ? appLanguage.localized(.ui.committing.label)
                            : appLanguage.localized(.ui.commit.selected))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !store.canCommitSelectedPaths
                        || store.isSelectedProjectActionBlocked
                        || store.recoveryState.commitSubmissionID != nil
                )
                .help(appLanguage.localized(.ui.commit.theSelectedFilesToTheSvnServerWith))
            }
        }
        .padding()
        .onChange(of: store.lastCompletedCommitMessage) { _, message in
            guard message != nil else { return }
            // 직접 커밋과 인증 후 재개된 커밋 모두 이 완료 이벤트 하나로 입력을 비웁니다.
            commitMessage = ""
            isCommitMessageFocused = false
            store.lastCompletedCommitMessage = nil
        }
        .sheet(item: $store.commitConfirmationRequest) { request in
            CommitConfirmationView(request: request)
                .environment(store)
        }
    }

    private func submitCommitAfterEndingTextInput() {
        guard let submissionID = store.recoveryState.beginCommitSubmission(
            isActionBlocked: store.isSelectedProjectActionBlocked,
            canCommit: store.canCommitSelectedPaths
        ) else { return }
        isCommitMessageFocused = false
        Task { @MainActor in
            defer { store.recoveryState.endCommitSubmission(submissionID) }
            // macOS TextField가 조합 중인 한글을 binding에 반영한 다음 메시지를 읽습니다.
            await Task.yield()
            let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !store.prepareCommitConfirmation(message: message) else { return }
            _ = await store.commitSelectedChanges(message: message)
        }
    }
}
