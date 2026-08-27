import AppKit
import SwiftUI

// Table/List 셀에서는 SwiftUI help의 호버 영역이 행의 contentShape에 가려질 수 있습니다.
private struct NativeIconHelpArea: NSViewRepresentable {
    let help: String

    func makeNSView(context _: Context) -> IconHelpTrackingView {
        IconHelpTrackingView(help: help)
    }

    func updateNSView(_ view: IconHelpTrackingView, context _: Context) {
        view.updateHelp(help)
    }
}

final class IconHelpTrackingView: NSView {
    init(help: String) {
        super.init(frame: .zero)
        setAccessibilityElement(false)
        updateHelp(help)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func updateHelp(_ help: String) {
        toolTip = help
    }

    override func hitTest(_: NSPoint) -> NSView? {
        // 툴팁 추적만 맡고 행 선택과 버튼 클릭은 아래 SwiftUI 뷰로 보냅니다.
        nil
    }
}

private struct IconHelpModifier: ViewModifier {
    let help: String

    func body(content: Content) -> some View {
        content
            .overlay {
                NativeIconHelpArea(help: help)
            }
            .help(help)
            .accessibilityLabel(help)
    }
}

extension View {
    func iconHelp(_ help: String) -> some View {
        modifier(IconHelpModifier(help: help))
    }
}
