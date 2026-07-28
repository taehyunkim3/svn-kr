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

@Test func applicationErrorHostsUseDetailedPresenterInsteadOfRootAlert() throws {
    let sources = svnMacSources()
    let content = try String(
        contentsOf: sources.appendingPathComponent("ContentView.swift"),
        encoding: .utf8
    )
    let expectedHosts = [
        "UpdatePreviewView.swift",
        "IgnoreRulesView.swift",
        "RepositoryLocksView.swift",
        "ConflictResolutionView.swift",
        "FileHistoryView.swift",
    ]

    #expect(!content.contains(".alert(appLanguage.text(\"오류\", \"Error\")"))
    #expect(content.contains(".detailedErrorPresenter(errorMessage: $store.errorMessage)"))

    let dialogs = try String(
        contentsOf: sources.appendingPathComponent("RepositoryDialogs.swift"),
        encoding: .utf8
    )
    #expect(dialogs.components(separatedBy: ".detailedErrorPresenter(errorMessage: $store.errorMessage)").count - 1 == 2)

    for file in expectedHosts {
        let source = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        #expect(
            source.contains(".detailedErrorPresenter(errorMessage: $store.errorMessage)"),
            "Missing presenter in \(file)"
        )
    }
}

@Test func checkoutAndRecoveryErrorsExposeCopyAndScrolling() throws {
    let sources = svnMacSources()
    let dialogs = try String(
        contentsOf: sources.appendingPathComponent("RepositoryDialogs.swift"),
        encoding: .utf8
    )
    let recovery = try String(
        contentsOf: sources.appendingPathComponent("WorkingCopyRecoveryView.swift"),
        encoding: .utf8
    )

    #expect(dialogs.contains("ErrorCopyButton(message: errorMessage)"))
    #expect(dialogs.contains("store.checkoutLog"))
    #expect(recovery.contains("ErrorDetailsText("))
    #expect(recovery.contains("message: error"))
    #expect(recovery.contains("ErrorCopyButton(message: error)"))
}

@Test func updatePreviewAllowsRecoveryWhenDeletedDirectoryHidesRemoteChanges() throws {
    let source = try String(
        contentsOf: svnMacSources().appendingPathComponent("UpdatePreviewView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("!store.remoteChanges.isEmpty || store.isWorkingCopyOutOfDate == true"))
    #expect(source.contains("삭제 예정 경로의 서버 변경은 목록에 표시되지 않을 수 있습니다."))
    #expect(source.contains("업데이트 실행"))
}

private func svnMacSources() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}
