import SVNCore
import SwiftUI

struct SVNLogMessageView: View {
    let entry: SVNLogEntry

    @Environment(\.appLanguage) private var appLanguage
    @State private var showsOriginalMessage = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.message.isEmpty ? appLanguage.text("커밋 메시지 없음", "No commit message") : entry.message)
                .textSelection(.enabled)

            if let originalMessage = entry.originalMessage {
                Button(appLanguage.text("복원됨", "Restored")) {
                    showsOriginalMessage = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(appLanguage.text("복원 전 원문 보기", "View the original message before restoration"))
                .popover(isPresented: $showsOriginalMessage) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appLanguage.text("복원 전 원문", "Original Message"))
                            .font(.headline)
                        Text(originalMessage)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(minWidth: 360, idealWidth: 520, maxWidth: 640)
                }
            }
        }
    }
}
