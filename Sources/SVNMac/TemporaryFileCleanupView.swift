import SwiftUI

/// 업데이트 뒤 내용 검증을 통과한 저장소 임시파일만 사용자가 최종 선택해 정리합니다.
struct TemporaryFileCleanupView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text(appLanguage.localized(.ui.repository.temporaryFileCleanup))
                    .font(.title2.bold())
                Spacer()
                Button(appLanguage.localized(.ui.close.label)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            Text(appLanguage.localized(.ui.review.verifiedFilesBeforeDeletingAndCommitt))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()

            List {
                ForEach(store.temporaryFileCleanupAssessments) { assessment in
                    if let failure = assessment.failure {
                        cleanupRejectedRow(path: assessment.path, reason: validationReason(failure))
                    } else {
                        Toggle(assessment.path, isOn: Binding(
                            get: { store.selectedTemporaryFileCleanupPaths.contains(assessment.path) },
                            set: { selected in
                                if selected { store.selectedTemporaryFileCleanupPaths.insert(assessment.path) }
                                else { store.selectedTemporaryFileCleanupPaths.remove(assessment.path) }
                            }
                        ))
                        .font(.body.monospaced())
                    }
                }

                ForEach(store.temporaryFileCleanupFailures) { failure in
                    cleanupRejectedRow(path: failure.path, reason: failure.reason)
                }
            }

            Divider()
            HStack {
                Text(appLanguage.localized(
                    .ui.selected.label,
                    store.selectedTemporaryFileCleanupPaths.count
                ))
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await store.confirmRepositoryTemporaryFileCleanup() }
                } label: {
                    ActionProgressLabel(
                        title: appLanguage.localized(.ui.delete.andCommitCleanup),
                        inProgressTitle: appLanguage.localized(.ui.cleaning.andCommitting),
                        isInProgress: store.isCleaningSelectedProjectTemporaryFiles
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.selectedTemporaryFileCleanupPaths.isEmpty
                        || store.isCleaningSelectedProjectTemporaryFiles
                )
            }
            .padding()
        }
        .appSheetFrame(minimumSize: AppLayout.temporaryFileCleanupSheetMinimumSize)
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private func cleanupRejectedRow(path: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(path).font(.body.monospaced())
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func validationReason(_ failure: TemporaryFileCleanupValidationFailure) -> String {
        switch failure {
        case let .officeLockFileTooLarge(maximumBytes):
            appLanguage.localized(failure.localizationKey, maximumBytes)
        default:
            appLanguage.localized(failure.localizationKey)
        }
    }
}
