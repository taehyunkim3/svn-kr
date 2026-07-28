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
                .help(appLanguage.text("복원 전 원문 보기", "View the original message before restoration"))
                .popover(isPresented: $showsOriginalMessage) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appLanguage.text("복원 전 원문", "Original Message"))
                            .font(.headline)
                        Text(appLanguage.text(
                            "이 커밋 메시지는 잘못된 인코딩으로 저장되어 복원 후 표시하고 있습니다. 다른 SVN 사용자에게는 아래 원문이 표시될 수 있습니다.",
                            "This commit message was saved with incorrect encoding and is shown after restoration. Other SVN users may see the original message below."
                        ))
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
