import SwiftUI
import SVNCore

enum WorkingCopyStatusTone: Equatable {
    case blue
    case gray
    case orange
    case purple
    case red

    var color: Color {
        switch self {
        case .blue: .blue
        case .gray: .gray
        case .orange: .orange
        case .purple: .purple
        case .red: .red
        }
    }
}

enum WorkingCopyStatusPolicy {
    static func allowsRevert(_ entry: SVNStatusEntry) -> Bool {
        entry.item != .incomplete
    }

    static func showsIncompleteRecovery(_ entry: SVNStatusEntry) -> Bool {
        entry.item == .incomplete
    }

    static func showsObstructionGuidance(_ entry: SVNStatusEntry) -> Bool {
        entry.item == .obstructed
    }

    static func showsSwitchedWarning(_ entry: SVNStatusEntry) -> Bool {
        entry.isSwitched
    }

    static func tone(for item: SVNStatusKind) -> WorkingCopyStatusTone {
        switch item {
        case .modified, .obstructed: .orange
        case .added, .unversioned: .blue
        case .deleted, .missing, .conflicted, .incomplete: .red
        case .replaced: .purple
        case .ignored, .unknown: .gray
        }
    }
}

struct StatusBadge: View {
    enum Style {
        case filled
        case tinted
    }

    let label: String
    let color: Color
    var style: Style = .filled
    var verticalPadding: CGFloat = 3

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(style == .filled ? Color.white : color)
            .padding(.horizontal, 6)
            .padding(.vertical, verticalPadding)
            .background(
                style == .filled ? color : color.opacity(0.12),
                in: Capsule()
            )
            .accessibilityLabel(label)
    }
}

extension SVNChangeAction {
    var presentationColor: Color {
        switch self {
        case .added: .blue
        case .modified: .orange
        case .deleted: .red
        case .replaced: .purple
        case .unknown: .gray
        }
    }
}
