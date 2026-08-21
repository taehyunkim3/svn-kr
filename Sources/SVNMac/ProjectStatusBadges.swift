import SwiftUI

struct ProjectStatusBadges: View {
    @Environment(\.appLanguage) private var appLanguage
    let summary: ProjectStatusSummary?
    let hasFilenameNormalizationWarning: Bool

    var body: some View {
        if summary != nil || hasFilenameNormalizationWarning {
            HStack(spacing: 7) {
                if hasFilenameNormalizationWarning {
                    Label(
                        appLanguage.localized("ui.filename.warning.52af346c"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .help(appLanguage.localized("ui.this.disk.stores.korean.filenames.in.decomposed..fe399d66"))
                }
                if let summary {
                    if summary.conflictCount > 0 {
                        Label("\(summary.conflictCount)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if summary.localChangeCount > 0 {
                        Label("\(summary.localChangeCount)", systemImage: "pencil")
                            .foregroundStyle(.orange)
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
            }
            .font(.caption2)
        }
    }
}
