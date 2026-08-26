import Foundation
import Testing
@testable import SVNMac

@Test func fileBrowserViewModeDefaultsToSplitAndRestoresStoredSelection() {
    let suiteName = "file-browser-view-mode-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(AppSettings.defaultFileBrowserViewMode == FileBrowserViewMode.split.rawValue)
    #expect(AppSettings.fileBrowserViewMode(in: defaults) == .split)

    defaults.set(FileBrowserViewMode.tree.rawValue, forKey: AppSettings.fileBrowserViewModeKey)
    let restoredDefaults = UserDefaults(suiteName: suiteName)!
    #expect(AppSettings.fileBrowserViewMode(in: restoredDefaults) == .tree)

    defaults.set("unknown", forKey: AppSettings.fileBrowserViewModeKey)
    #expect(AppSettings.fileBrowserViewMode(in: defaults) == .split)
}

@Test func splitBrowserFolderRowsSupportDoubleClickAndChevronHitArea() throws {
    #expect(AppLayout.fileBrowserFolderDisclosureHitTargetSize.width >= 20)
    #expect(AppLayout.fileBrowserFolderDisclosureHitTargetSize.height >= 20)

    let source = try source(at: "Sources/SVNMac/WorkingCopySplitBrowserView.swift")
    let folderRowStart = try #require(source.range(of: "private func folderRow"))
    let nextFunctionStart = try #require(
        source.range(of: "private func fileNameCell", range: folderRowStart.upperBound..<source.endIndex)
    )
    let folderRow = source[folderRowStart.lowerBound..<nextFunctionStart.lowerBound]
    let chevronBranchEnd = try #require(folderRow.range(of: "} else {"))
    let chevronBranch = folderRow[..<chevronBranchEnd.lowerBound]
    let hitFrame = try #require(chevronBranch.range(of: ".frame("))
    let contentShape = try #require(chevronBranch.range(of: ".contentShape(Rectangle())"))

    #expect(chevronBranch.contains("AppLayout.fileBrowserFolderDisclosureHitTargetSize.width"))
    #expect(chevronBranch.contains("AppLayout.fileBrowserFolderDisclosureHitTargetSize.height"))
    #expect(hitFrame.lowerBound < contentShape.lowerBound)
    #expect(folderRow.contains("TapGesture(count: 2)"))
    #expect(folderRow.contains("browserState.enterDirectory(row.relativePath)"))
}

@Test func filesTabSwitchesBetweenPersistentTreeAndSplitBrowsers() throws {
    let contentView = try source(at: "Sources/SVNMac/ContentView.swift")

    #expect(contentView.contains("@AppStorage(AppSettings.fileBrowserViewModeKey)"))
    #expect(contentView.contains("viewModeIdentifier: $fileBrowserViewModeIdentifier"))
    #expect(contentView.contains("Picker("))
    #expect(contentView.contains(".pickerStyle(.segmented)"))
    #expect(contentView.contains("WorkingCopyBrowserView(searchText: $searchText)"))
    #expect(contentView.contains("WorkingCopySplitBrowserView()"))

    // 최초 분할 보기 진입 뒤에는 화면 상태와 디렉터리 캐시를 유지한 채 표시만 전환합니다.
    #expect(contentView.contains("@State private var hasActivatedSplitView"))
    #expect(contentView.contains("if hasActivatedSplitView"))
    #expect(contentView.contains("viewMode == .tree || !normalizedSearchText.isEmpty"))
    #expect(contentView.contains("viewMode == .split && normalizedSearchText.isEmpty"))
}

@Test func duplicateFileBrowserColumnKeysAreRemovedFromSources() throws {
    let removedKeys = [
        "ui.file.browser.kind." + "98b7d2e4",
        "ui.file.browser.modified.date." + "6cb3548f",
        "ui.file.browser.name." + "03fe9d71",
        "ui.file.browser.size." + "a77c1e02",
    ]
    let sources = repositoryRoot().appendingPathComponent("Sources/SVNMac", isDirectory: true)
    let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))

    for case let fileURL as URL in enumerator {
        guard ["swift", "strings", "xcstrings"].contains(fileURL.pathExtension) else { continue }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        for key in removedKeys {
            #expect(!contents.contains(key), "\(key) remains in \(fileURL.path)")
        }
    }
}

@Test func sharedFileBrowserColumnKeysAreLocalizedInKoreanAndEnglish() throws {
    let expectedValues: [(key: LocalizationKey, korean: String, english: String)] = [
        (.ui.browser.name, "이름", "Name"),
        (.ui.browser.dateModified, "수정일", "Date Modified"),
        (.ui.browser.size, "크기", "Size"),
        (.ui.browser.kind, "종류", "Kind"),
    ]
    let koreanStrings = try source(at: "Sources/SVNMac/Resources/ko.lproj/Localizable.strings")
    let englishStrings = try source(at: "Sources/SVNMac/Resources/en.lproj/Localizable.strings")

    for entry in expectedValues {
        #expect(koreanStrings.contains("\"\(entry.key.rawValue)\" ="))
        #expect(englishStrings.contains("\"\(entry.key.rawValue)\" ="))
        #expect(AppLanguage.korean.localized(entry.key) == entry.korean)
        #expect(AppLanguage.english.localized(entry.key) == entry.english)
    }
}

private func source(at path: String) throws -> String {
    try String(
        contentsOf: repositoryRoot().appendingPathComponent(path),
        encoding: .utf8
    )
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
