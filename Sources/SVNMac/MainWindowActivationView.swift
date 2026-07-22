import AppKit
import SwiftUI

/// SwiftUI 콘텐츠가 실제로 붙은 메인 창의 key 상태만 감시합니다.
@MainActor
final class MainWindowActivationMonitor: NSObject {
    private weak var observedWindow: NSWindow?
    private let onActivation: () -> Void

    init(onActivation: @escaping () -> Void) {
        self.onActivation = onActivation
    }

    func observe(_ window: NSWindow?) {
        guard observedWindow !== window else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: observedWindow
        )
        observedWindow = window
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        if window.isKeyWindow { onActivation() }
    }

    @objc private func windowDidBecomeKey() {
        onActivation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
private final class WindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

/// 보이지 않는 NSView를 통해 이 SwiftUI 계층을 호스팅하는 창을 추적합니다.
struct MainWindowActivationView: NSViewRepresentable {
    let onActivation: () -> Void

    func makeCoordinator() -> MainWindowActivationMonitor {
        MainWindowActivationMonitor(onActivation: onActivation)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        view.onWindowChange = context.coordinator.observe
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.observe(nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: MainWindowActivationMonitor) {
        coordinator.observe(nil)
    }
}
