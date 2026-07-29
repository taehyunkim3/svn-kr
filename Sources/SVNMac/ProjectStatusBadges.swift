import SwiftUI

struct ProjectStatusBadges: View {
    @Environment(\.appLanguage) private var appLanguage
    let summary: ProjectStatusSummary?

    var body: some View {
        if let summary {
            HStack(spacing: 7) {
                if summary.conflictCount > 0 {
                    Label("\(summary.conflictCount)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if summary.localChangeCount > 0 {
                    Label("\(summary.localChangeCount)", systemImage: "pencil").foregroundStyle(.orange)
                }
                if summary.lockCount > 0 {
                    Label("\(summary.lockCount)", systemImage: "lock.fill")
                        .foregroundStyle(.blue)
                        .help(appLanguage.localized("ui.locked.files.457daf19", summary.lockCount))
                }
                if summary.needsUpdate {
                    Label(appLanguage.localized("ui.update.0f38eb76"), systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2)
        }
    }
}
