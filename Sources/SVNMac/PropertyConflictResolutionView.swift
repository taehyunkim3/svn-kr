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
            Button(appLanguage.localized("ui.cancel.a2ce2c22"), role: .cancel) {
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
                appLanguage.localized("ui.property.conflict.2fd61b8a"),
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
                    appLanguage.localized("ui.the.macos.unicode.path.was.matched.to.the.actual.0575e471"),
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
                    title: appLanguage.localized("ui.apply.server.properties.51ad840e"),
                    description: appLanguage.localized("ui.replace.local.properties.with.server.values.c2804d9a"),
                    warning: appLanguage.localized("ui.local.property.values.will.be.discarded.f98a7c20"),
                    choice: .applyServerProperties
                )

                choiceCard(
                    title: appLanguage.localized("ui.keep.my.properties.68b12ae4"),
                    description: appLanguage.localized("ui.keep.local.properties.as.resolved.values.4a0d2c6f"),
                    warning: appLanguage.localized("ui.server.property.values.will.be.discarded.84d6f2c1"),
                    choice: .keepMyProperties
                )
            }
        }
    }

    private func propertyNamesDescription(_ propertyNames: [String]) -> String {
        guard !propertyNames.isEmpty else {
            return appLanguage.localized("ui.conflicted.property.name.unavailable.0cc5d784")
        }
        return appLanguage.localized("ui.conflicted.properties.849bf370", propertyNames.joined(separator: ", "))
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
                            inProgressTitle: appLanguage.localized("ui.resolving.d5e0b71c"),
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
            appLanguage.localized("ui.apply.server.properties.51ad840e")
        case .keepMyProperties:
            appLanguage.localized("ui.keep.my.properties.68b12ae4")
        }
    }

    private func warningMessage(for choice: PropertyConflictResolutionChoice) -> String {
        switch choice {
        case .applyServerProperties:
            appLanguage.localized("ui.local.property.values.will.be.discarded.f98a7c20")
        case .keepMyProperties:
            appLanguage.localized("ui.server.property.values.will.be.discarded.84d6f2c1")
        }
    }

    private var footer: some View {
        HStack {
            Text(appLanguage.localized("ui.property.conflict.blocks.commit.until.resolved.bf3c8a12"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appLanguage.localized("ui.cancel.a2ce2c22")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(store.isResolvingConflict)
        }
    }
}
