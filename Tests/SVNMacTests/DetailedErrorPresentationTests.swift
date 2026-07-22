import AppKit
import Testing
@testable import SVNMac

@MainActor
@Test func errorClipboardCopiesLongMultilineMessageWithoutModification() {
    let pasteboard = NSPasteboard(name: .init("DetailedErrorPresentationTests"))
    let message = "svn info 실패: 첫 줄\n경로: /한글 폴더/아주-긴-파일명.xlsx\nsvn: E200009: 상세 원문"

    #expect(ErrorClipboard.copy(message, to: pasteboard))
    #expect(pasteboard.string(forType: .string) == message)
}

@Test func detailedErrorViewProvidesScrollableSelectableCopyableContent() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("DetailedErrorView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("ScrollView([.horizontal, .vertical])"))
    #expect(source.contains(".textSelection(.enabled)"))
    #expect(source.contains("ErrorCopyButton"))
    #expect(source.contains("detailedErrorPresenter"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
