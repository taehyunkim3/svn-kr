import SVNCore
import SwiftUI

struct SVNLogMessageView: View {
    let entry: SVNLogEntry

    @Environment(\.appLanguage) private var appLanguage
    @State private var showsOriginalMessage = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.message.isEmpty ? appLanguage.localized(.ui.commit.noCommitMessage) : entry.message)
                .textSelection(.enabled)

            if let originalMessage = entry.originalMessage {
                Button(appLanguage.localized(.ui.history.restored)) {
                    showsOriginalMessage = true
                }
                .help(appLanguage.localized(.ui.history.viewOriginalMessageBeforeRestoration))
                .popover(isPresented: $showsOriginalMessage) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appLanguage.localized(.ui.history.originalMessage))
                            .font(.headline)
                        Text(appLanguage.localized(.ui.commit.messageSavedIncorrectEncodingShownAfterRestorationOtherSvnUsers))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(originalMessage)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(
                        minWidth: AppLayout.logMessagePopoverMinimumWidth,
                        idealWidth: AppLayout.logMessagePopoverIdealWidth,
                        maxWidth: AppLayout.logMessagePopoverMaximumWidth
                    )
                }
            }
        }
    }
}
