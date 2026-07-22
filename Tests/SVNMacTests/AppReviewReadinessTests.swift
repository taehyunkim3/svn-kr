import Foundation
import Testing
@testable import SVNMac

@Suite("AppReviewReadinessTests")
struct AppReviewReadinessTests {
    @MainActor
    @Test func demoStoreProvidesReviewableSampleDataWithoutLiveServices() {
        let store = ProjectStore.demo()

        #expect(store.isDemoMode)
        #expect(!store.projects.isEmpty)
        #expect(!store.statuses.isEmpty)
        #expect(!store.logs.isEmpty)
        #expect(!store.workingCopyFileTree.isEmpty)
        #expect(store.selectedProject != nil)
    }

    @Test func installedNameMatchesAppStoreNameWithoutChangingBundleIdentifier() throws {
        let root = repositoryRoot()
        let plist = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let values = try #require(
            PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        )

        #expect(values["CFBundleName"] as? String == "SVN for Mac")
        #expect(values["CFBundleIdentifier"] as? String == "com.mrdevello.svnmac")
    }

    @Test func firstRunRepositorySheetExposesSampleProjectEntry() throws {
        let source = try repositorySource("RepositoryDialogs.swift")

        #expect(source.contains("샘플 프로젝트 둘러보기"))
        #expect(source.contains("Browse Sample Project"))
        #expect(source.contains("onBrowseDemo()"))
    }

    @Test func supportedLanguagesExposeNativeDisplayNames() {
        #expect(AppLanguage.allCases.map(\.displayName) == ["한국어", "English"])
    }

    @Test func firstRunRepositorySheetExposesExtensibleLanguageMenu() throws {
        let source = try repositorySource("RepositoryDialogs.swift")

        #expect(source.contains("@AppStorage(AppSettings.languageKey)"))
        #expect(source.contains("ForEach(AppLanguage.allCases"))
        #expect(source.contains("appLanguage.text(\"언어\", \"Language\")"))
        #expect(source.contains("systemImage: \"globe\""))
    }

    @Test func sampleEntryIsSecondaryAndPlacedWithTrailingActions() throws {
        let file = try repositorySource("RepositoryDialogs.swift")
        let viewStart = try #require(file.range(of: "struct AddRepositoryView: View"))
        let viewEnd = try #require(file.range(of: "struct CredentialsView: View"))
        let source = String(file[viewStart.lowerBound..<viewEnd.lowerBound])
        let register = try #require(source.range(of: "Button(appLanguage.text(\"기존 로컬 폴더 등록…\""))
        let sample = try #require(source.range(of: "Button(appLanguage.text(\"샘플 프로젝트 둘러보기\""))
        let cancel = try #require(source.range(of: "Button(appLanguage.text(\"취소\""))
        let spacer = register.lowerBound < sample.lowerBound
            ? source.range(of: "Spacer()", range: register.upperBound..<sample.lowerBound)
            : nil

        #expect(register.lowerBound < sample.lowerBound)
        #expect(sample.lowerBound < cancel.lowerBound)
        #expect(spacer != nil)
    }

    @Test func demoExitUsesVisibleOrangeTextButton() throws {
        let source = try repositorySource("ContentView.swift")
        let start = try #require(source.range(of: "Button(appLanguage.text(\"데모 종료\", \"Exit Demo\"))"))
        let end = try #require(source.range(
            of: "Text(appLanguage.text(\"새로고침\", \"Refresh\"))",
            range: start.upperBound..<source.endIndex
        ))
        let demoButton = String(source[start.lowerBound..<end.lowerBound])

        #expect(demoButton.contains(".buttonStyle(.borderedProminent)"))
        #expect(demoButton.contains(".tint(.orange)"))
        #expect(!demoButton.contains("systemImage:"))
    }

    @Test func exitingEnvironmentDemoReturnsToLiveStore() throws {
        let source = try repositorySource("SVNMacApp.swift")

        #expect(source.contains("_liveStore = StateObject(wrappedValue: ProjectStore())"))
        #expect(source.contains("_demoStore = StateObject(wrappedValue: ProjectStore.demo())"))
    }

    private func repositorySource(_ filename: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/SVNMac/\(filename)"),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
