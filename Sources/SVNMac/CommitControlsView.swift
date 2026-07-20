import SwiftUI

/// 커밋 메시지 입력 갱신을 대용량 변경 파일 목록과 분리합니다.
struct CommitControlsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var commitMessage = ""
    @FocusState private var isCommitMessageFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField(appLanguage.text("커밋 메시지", "Commit message"), text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .focused($isCommitMessageFocused)
                .onSubmit { submitCommitAfterEndingTextInput() }
            HStack {
                Button(appLanguage.text("전체 선택", "Select All")) {
                    store.selectedPaths = store.selectableStatusPaths
                }
                .help(appLanguage.text("현재 변경된 파일을 모두 커밋 대상으로 선택합니다.", "Select all currently changed files for commit."))
                Button(appLanguage.text("선택 해제", "Clear Selection")) { store.selectedPaths.removeAll() }
                    .help(appLanguage.text("현재 선택된 커밋 대상을 모두 해제합니다.", "Clear all selected commit targets."))
                Spacer()
                Text(appLanguage.text("\(store.selectedPaths.count)개 선택", "\(store.selectedPaths.count) selected"))
                    .foregroundStyle(.secondary)
                Button(action: submitCommitAfterEndingTextInput) {
                    HStack(spacing: 6) {
                        if store.isCommittingSelectedProject {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.isCommittingSelectedProject
                            ? appLanguage.text("커밋 중…", "Committing…")
                            : appLanguage.text("선택 항목 커밋", "Commit Selected"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canCommitSelectedPaths || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                .help(appLanguage.text("선택한 파일을 입력한 메시지로 SVN 서버에 커밋합니다.", "Commit the selected files to the SVN server with the entered message."))
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
    }

    private func submitCommit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        Task { _ = await store.commit(message: message) }
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
