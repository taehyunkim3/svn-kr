import AppKit
import Foundation
import Testing
@testable import SVNMac

@MainActor
@Test func activationMonitorObservesOneWindowOnceAndMovesToReplacementWindow() {
    let first = NSWindow(
        contentRect: .zero,
        styleMask: [],
        backing: .buffered,
        defer: false
    )
    let second = NSWindow(
        contentRect: .zero,
        styleMask: [],
        backing: .buffered,
        defer: false
    )
    var activationCount = 0
    let monitor = MainWindowActivationMonitor { activationCount += 1 }

    monitor.observe(first)
    monitor.observe(first)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    #expect(activationCount == 1)

    monitor.observe(second)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second)
    #expect(activationCount == 2)
}

@Test func contentViewUsesMainWindowActivationForLocalOnlyRefresh() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac/ContentView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("MainWindowActivationView"))
    #expect(source.contains("store.refreshForMainWindowActivation()"))
    #expect(!source.contains(#"@Environment(\.scenePhase)"#))
}
