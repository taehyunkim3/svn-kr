import SwiftUI

struct CommitMessageDrafts {
    private var messagesByProjectID: [SVNProject.ID: String] = [:]

    func message(for projectID: SVNProject.ID?) -> String {
        guard let projectID else { return "" }
        return messagesByProjectID[projectID] ?? ""
    }

    mutating func setMessage(_ message: String, for projectID: SVNProject.ID?) {
        guard let projectID else { return }
        messagesByProjectID[projectID] = message
    }

    mutating func clearMessage(for projectID: SVNProject.ID?) {
        guard let projectID else { return }
        messagesByProjectID[projectID] = nil
    }
}

/// 커밋 메시지 입력 갱신을 대용량 변경 파일 목록과 분리합니다.
struct CommitControlsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @State private var commitMessageDrafts = CommitMessageDrafts()
    @FocusState private var isCommitMessageFocused: Bool

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 8) {
            TextField(appLanguage.localized(.ui.commit.message), text: commitMessage)
                .textFieldStyle(.roundedBorder)
                .focused($isCommitMessageFocused)
                .onSubmit { submitCommitAfterEndingTextInput() }
            HStack {
                Button(appLanguage.localized(.ui.commit.selectAll)) {
                    store.selectedPaths = store.selectAllStatusPaths
                }
                .help(appLanguage.localized(.ui.commit.selectAllCurrentlyChangedFilesCommit))
                Button(appLanguage.localized(.ui.commit.clearSelection)) { store.selectedPaths.removeAll() }
                    .help(appLanguage.localized(.ui.commit.clearAllSelectedCommitTargets))
                if store.isCommitInteractionLocked {
                    Text(appLanguage.localized(.ui.commit.committing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appLanguage.localized(.ui.common.selectedCount, store.selectedPaths.count))
                    .foregroundStyle(.secondary)
                if store.scheduledDeletionCount > 0 {
                    Text(appLanguage.localized(.ui.commit.pendingDeletionCount, store.scheduledDeletionCount))
                    .foregroundStyle(.red)
                }
                Button(action: submitCommitAfterEndingTextInput) {
                    HStack(spacing: 6) {
                        if store.isCommittingSelectedProject {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.isCommittingSelectedProject
                            ? appLanguage.localized(.ui.commit.committing)
                            : appLanguage.localized(.ui.commit.selected))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !store.canCommitSelectedPaths
                        || store.isCommitInteractionLocked
                        || store.recoveryState.commitSubmissionID != nil
                )
                .help(appLanguage.localized(.ui.commit.selectedFilesSvnServerEnteredMessage))
            }
        }
        .padding()
        .disabled(store.isCommitInteractionLocked)
        .onChange(of: store.lastCompletedCommitMessage) { _, message in
            guard message != nil else { return }
            // 직접 커밋과 인증 후 재개된 커밋 모두 이 완료 이벤트 하나로 입력을 비웁니다.
            commitMessageDrafts.clearMessage(for: store.selectedProjectID)
            isCommitMessageFocused = false
            store.lastCompletedCommitMessage = nil
        }
        .onChange(of: store.selectedProjectID) { _, _ in
            isCommitMessageFocused = false
        }
        .sheet(item: $store.commitConfirmationRequest) { request in
            CommitConfirmationView(request: request)
                .environment(store)
        }
    }

    private func submitCommitAfterEndingTextInput() {
        guard let submissionProjectID = store.selectedProjectID,
              let submissionID = store.recoveryState.beginCommitSubmission(
            isActionBlocked: store.isCommitInteractionLocked,
            canCommit: store.canCommitSelectedPaths
        ) else { return }
        isCommitMessageFocused = false
        Task { @MainActor in
            defer { store.recoveryState.endCommitSubmission(submissionID) }
            // macOS TextField가 조합 중인 한글을 binding에 반영한 다음 메시지를 읽습니다.
            await Task.yield()
            guard store.selectedProjectID == submissionProjectID else { return }
            let message = commitMessageDrafts.message(for: submissionProjectID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !store.prepareCommitConfirmation(message: message) else { return }
            _ = await store.commitSelectedChanges(message: message)
        }
    }

    private var commitMessage: Binding<String> {
        Binding(
            get: { commitMessageDrafts.message(for: store.selectedProjectID) },
            set: { commitMessageDrafts.setMessage($0, for: store.selectedProjectID) }
        )
    }
}
