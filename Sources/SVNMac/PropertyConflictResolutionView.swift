import SwiftUI

struct PropertyConflictResolutionView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChoice: PropertyConflictResolutionChoice?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            if let session = store.recoveryState.propertyConflictSession {
                conflictBody(session)
            }
            Spacer()
            Divider()
            footer
        }
        .padding()
        .appSheetFrame(minimumSize: AppLayout.conflictResolutionSheetMinimumSize)
        .interactiveDismissDisabled(store.isResolvingConflict)
        .alert(
            confirmationTitle,
            isPresented: .isPresenting($pendingChoice)
        ) {
            Button(confirmationActionTitle, role: .destructive) {
                guard let choice = pendingChoice else { return }
                pendingChoice = nil
                Task { await store.resolveActivePropertyConflict(using: choice) }
            }
            Button(appLanguage.localized(.ui.cancel.label), role: .cancel) {
                pendingChoice = nil
            }
        } message: {
            if let choice = pendingChoice {
                Text(warningMessage(for: choice))
            }
        }
        .detailedErrorPresenter(errorMessage: $store.errorMessage)
    }

    private var header: some View {
        HStack {
            Label(
                appLanguage.localized(.ui.property.conflict),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.orange)
            Spacer()
        }
    }

    private func conflictBody(_ session: PropertyConflictSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.wasCanonicallyResolved {
                Label(
                    appLanguage.localized(.ui.the.macosUnicodePathWasMatchedToTheActual),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(session.requestedPath.precomposedStringWithCanonicalMapping)
                .lineLimit(1)
                .textSelection(.enabled)

            Text(propertyNamesDescription(session.propertyNames))
                .foregroundStyle(session.propertyNames.isEmpty ? .secondary : .primary)

            HStack(alignment: .top, spacing: 14) {
                choiceCard(
                    title: appLanguage.localized(.ui.apply.serverProperties),
                    description: appLanguage.localized(.ui.replace.localPropertiesWithServerValues),
                    warning: appLanguage.localized(.ui.local.propertyValuesWillBeDiscarded),
                    choice: .applyServerProperties
                )

                choiceCard(
                    title: appLanguage.localized(.ui.keep.myProperties),
                    description: appLanguage.localized(.ui.keep.localPropertiesAsResolvedValues),
                    warning: appLanguage.localized(.ui.server.propertyValuesWillBeDiscarded),
                    choice: .keepMyProperties
                )
            }
        }
    }

    private func propertyNamesDescription(_ propertyNames: [String]) -> String {
        guard !propertyNames.isEmpty else {
            return appLanguage.localized(.ui.conflicted.propertyNameUnavailable)
        }
        return appLanguage.localized(.ui.conflicted.properties, propertyNames.joined(separator: ", "))
    }

    private func choiceCard(
        title: String,
        description: String,
        warning: String,
        choice: PropertyConflictResolutionChoice
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                Text(description)
                    .foregroundStyle(.secondary)
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Spacer()
                    Button {
                        pendingChoice = choice
                    } label: {
                        ActionProgressLabel(
                            title: title,
                            inProgressTitle: appLanguage.localized(.ui.resolving.label),
                            isInProgress: store.isResolvingConflict
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isResolvingConflict)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var confirmationTitle: String {
        guard let choice = pendingChoice else { return "" }
        return title(for: choice)
    }

    private var confirmationActionTitle: String {
        guard let choice = pendingChoice else { return "" }
        return title(for: choice)
    }

    private func title(for choice: PropertyConflictResolutionChoice) -> String {
        switch choice {
        case .applyServerProperties:
            appLanguage.localized(.ui.apply.serverProperties)
        case .keepMyProperties:
            appLanguage.localized(.ui.keep.myProperties)
        }
    }

    private func warningMessage(for choice: PropertyConflictResolutionChoice) -> String {
        switch choice {
        case .applyServerProperties:
            appLanguage.localized(.ui.local.propertyValuesWillBeDiscarded)
        case .keepMyProperties:
            appLanguage.localized(.ui.server.propertyValuesWillBeDiscarded)
        }
    }

    private var footer: some View {
        HStack {
            Text(appLanguage.localized(.ui.property.conflictBlocksCommitUntilResolved))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appLanguage.localized(.ui.cancel.label)) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isResolvingConflict)
        }
    }
}
