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
                        appLanguage.localized(.ui.status.filenameWarning),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .help(appLanguage.localized(.ui.status.diskContainingFolderStoresKoreanFilenamesOnlyDecomposedFormFilenames))
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
                            .help(appLanguage.localized(.ui.status.lockedFiles, summary.lockCount))
                    }
                    if summary.needsUpdate {
                        Label(appLanguage.localized(.ui.update.update), systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.caption2)
        }
    }
}
