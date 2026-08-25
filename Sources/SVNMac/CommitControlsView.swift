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
            TextField(appLanguage.localized("ui.commit.message.c5139167"), text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .focused($isCommitMessageFocused)
                .onSubmit { submitCommitAfterEndingTextInput() }
            HStack {
                Button(appLanguage.localized("ui.select.all.ef1f5eca")) {
                    store.selectedPaths = store.selectAllStatusPaths
                }
                .help(appLanguage.localized("ui.select.all.currently.changed.files.for.commit.ccad7410"))
                Button(appLanguage.localized("ui.clear.selection.6520660b")) { store.selectedPaths.removeAll() }
                    .help(appLanguage.localized("ui.clear.all.selected.commit.targets.605665f6"))
                Spacer()
                Text(appLanguage.localized("ui.selected.685ae833", store.selectedPaths.count))
                    .foregroundStyle(.secondary)
                if store.scheduledDeletionCount > 0 {
                    Text(appLanguage.localized("ui.pending.deletion.4b08f65b", store.scheduledDeletionCount))
                    .foregroundStyle(.red)
                }
                Button(action: submitCommitAfterEndingTextInput) {
                    HStack(spacing: 6) {
                        if store.isCommittingSelectedProject {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.isCommittingSelectedProject
                            ? appLanguage.localized("ui.committing.0e8ec0f4")
                            : appLanguage.localized("ui.commit.selected.29bc2086"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !store.canCommitSelectedPaths
                        || store.isSelectedProjectActionBlocked
                )
                .help(appLanguage.localized("ui.commit.the.selected.files.to.the.svn.server.with.8046c0f8"))
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

    private func submitCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !store.prepareCommitConfirmation(message: message) else { return }
        Task { _ = await store.commitSelectedChanges(message: message) }
    }

    private func submitCommitAfterEndingTextInput() {
        isCommitMessageFocused = false
        Task { @MainActor in
            // macOS TextField가 조합 중인 한글을 binding에 반영한 다음 메시지를 읽습니다.
            await Task.yield()
            submitCommit()
        }
    }
}
