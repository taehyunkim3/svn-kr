import AppKit
import SwiftUI
import Testing
@testable import SVNMac

@MainActor
@Test func iconHelpInstallsNativeTooltipInsideTableWithoutClaimingClicks() throws {
    let hostingView = NSHostingView(rootView: Table([IconHelpTestRow()]) {
        TableColumn("File") { _ in
            HStack {
                Image(systemName: "lock.square")
                    .iconHelp("Lock required before editing")
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    })
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    let trackingView = try #require(findIconHelpTrackingView(in: hostingView))
    #expect(trackingView.toolTip == "Lock required before editing")
    #expect(trackingView.frame.width > 0)
    #expect(trackingView.frame.height > 0)
    #expect(trackingView.hitTest(NSPoint(x: 1, y: 1)) == nil)
}

private struct IconHelpTestRow: Identifiable {
    let id = UUID()
}

@MainActor
private func findIconHelpTrackingView(in view: NSView) -> IconHelpTrackingView? {
    if let trackingView = view as? IconHelpTrackingView { return trackingView }
    return view.subviews.lazy.compactMap(findIconHelpTrackingView).first
}
