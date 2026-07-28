import SVNCore
import SwiftUI

struct SVNLogMessageView: View {
    let entry: SVNLogEntry

    @Environment(\.appLanguage) private var appLanguage
    @State private var showsOriginalMessage = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.message.isEmpty ? appLanguage.localized("ui.no.commit.message.911ccc29") : entry.message)
                .textSelection(.enabled)

            if let originalMessage = entry.originalMessage {
                Button(appLanguage.localized("ui.restored.98d96c01")) {
                    showsOriginalMessage = true
                }
                .help(appLanguage.localized("ui.view.the.original.message.before.restoration.6a5e3b2b"))
                .popover(isPresented: $showsOriginalMessage) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appLanguage.localized("ui.original.message.fbd14889"))
                            .font(.headline)
                        Text(appLanguage.localized("ui.this.commit.message.was.saved.with.incorrect.enc.355e2cb5"))
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
