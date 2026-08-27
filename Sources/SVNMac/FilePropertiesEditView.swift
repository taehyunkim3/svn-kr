import SwiftUI

struct FilePropertiesEditView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    let request: FilePropertiesEditRequest
    @State private var isNeedsLockEnabled = false
    @State private var initialNeedsLockValue: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                appLanguage.localized(.ui.repository.editFileProperties),
                systemImage: "slider.horizontal.3"
            )
            .font(.title2.bold())

            Text(request.relativePath.precomposedStringWithCanonicalMapping)
                .font(.callout.monospaced())
                .textSelection(.enabled)

            if initialNeedsLockValue != nil {
                Toggle(
                    appLanguage.localized(.ui.lock.requireBeforeEditingProperty),
                    isOn: $isNeedsLockEnabled
                )
                .disabled(store.isWorking)

                Label(
                    appLanguage.localized(.ui.lock.propertyChangeCommitRequired),
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let failure = store.recoveryState.filePropertiesEditFailureMessage {
                ErrorDetailsText(message: failure)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
            Divider()
            HStack {
                Spacer()
                Button(appLanguage.localized(.ui.common.cancel), role: .cancel) {
                    store.dismissFilePropertiesEdit()
                }
                .disabled(store.isWorking)
                Button(appLanguage.localized(.ui.common.save)) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(initialNeedsLockValue == nil || store.isWorking)
            }
        }
        .padding(24)
        .appSheetFrame(minimumSize: AppLayout.filePropertiesSheetMinimumSize)
        .task(id: request.id) {
            guard let isEnabled = await store.loadNeedsLockState(for: request) else { return }
            initialNeedsLockValue = isEnabled
            isNeedsLockEnabled = isEnabled
        }
        .interactiveDismissDisabled(store.isWorking)
    }

    private func save() {
        guard let initialNeedsLockValue else { return }
        guard initialNeedsLockValue != isNeedsLockEnabled else {
            store.dismissFilePropertiesEdit()
            return
        }
        Task {
            _ = await store.saveFileProperties(request, needsLock: isNeedsLockEnabled)
        }
    }
}
