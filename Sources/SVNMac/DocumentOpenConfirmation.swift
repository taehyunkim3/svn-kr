import SwiftUI

/// 문서 계열 파일을 열기 전에 저장소 잠금의 의미를 설명하고 사용자의 선택을 받습니다.
private struct DocumentOpenConfirmationModifier: ViewModifier {
    @Environment(ProjectStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.sheet(item: $store.documentOpenRequest) { request in
            DocumentOpenConfirmationView(request: request)
                .environment(store)
        }
    }
}

private struct DocumentOpenConfirmationView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @State private var remembersOpenWithoutLock = false

    let request: DocumentOpenRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized(.ui.lock.fileBeforeOpening),
                systemImage: "lock.doc"
            )
            .font(.title2.bold())

            requestMessage

            Spacer()

            Toggle(
                appLanguage.localized(.ui.lock.openWithoutLockingDonTAskAgain),
                isOn: $remembersOpenWithoutLock
            )
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.documentOpenRequest = nil
                }
                .keyboardShortcut(.cancelAction)

                if request.existingLock == nil {
                    // 다시 묻지 않기를 켜면 앞으로 잠그지 않고 여는 선택이므로
                    // 이 자리에서 잠그고 열기를 고를 수 없게 합니다.
                    Button(appLanguage.localized(.ui.lock.lockAndOpenAction)) {
                        Task { await store.lockAndOpen(request) }
                    }
                    .disabled(remembersOpenWithoutLock)
                }

                // 잠그고 열기는 다른 사람의 편집을 막으므로 Return 기본 동작으로 두지 않습니다.
                Button(appLanguage.localized(.ui.lock.openWithoutLock)) {
                    store.openWithoutLock(
                        request,
                        rememberingChoice: remembersOpenWithoutLock
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.documentOpenConfirmationSheetMinimumSize)
    }

    @ViewBuilder
    private var requestMessage: some View {
        if request.lockInformationWasUnavailable {
            Label(
                appLanguage.localized(.ui.lock.informationCouldNotCheckedCanOpenFileWithoutLockingIt),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        } else if let lock = request.existingLock {
            Text(
                appLanguage.localized(
                    .ui.lock.fileCurrentlyLockedOpeningWithoutLockMayPreventCommittingCause,
                    lock.owner
                )
            )
        } else {
            Text(appLanguage.localized(.ui.lock.lockingPreventsConcurrentCommitsOtherUsersReducesDocumentConflictsSuccessful))
        }
    }
}

extension View {
    func documentOpenConfirmation() -> some View {
        modifier(DocumentOpenConfirmationModifier())
    }
}
