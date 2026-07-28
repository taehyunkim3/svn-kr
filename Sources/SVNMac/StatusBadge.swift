import SwiftUI
import SVNCore

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
