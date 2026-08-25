import SVNCore
import SwiftUI

struct SVNLogMessageView: View {
    let entry: SVNLogEntry

    @Environment(\.appLanguage) private var appLanguage
    @State private var showsOriginalMessage = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.message.isEmpty ? appLanguage.localized(.ui.no.commitMessage) : entry.message)
                .textSelection(.enabled)

            if let originalMessage = entry.originalMessage {
                Button(appLanguage.localized(.ui.restored.label)) {
                    showsOriginalMessage = true
                }
                .help(appLanguage.localized(.ui.view.theOriginalMessageBeforeRestoration))
                .popover(isPresented: $showsOriginalMessage) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appLanguage.localized(.ui.original.message))
                            .font(.headline)
                        Text(appLanguage.localized(.ui.this.commitMessageWasSavedWithIncorrectEnc))
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
