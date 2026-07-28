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

        #expect(values["CFBundleName"] as? String == "SVN KR")
        #expect(values["CFBundleIdentifier"] as? String == "com.mrdevello.svnmac")
        #expect(values["NSHumanReadableCopyright"] as? String == "© 2026 Taehyun Kim")
    }

    @Test func packagedAppIncludesSwiftPMResourceBundleAtRuntimeLookupPath() throws {
        let script = try String(
            contentsOf: repositoryRoot().appendingPathComponent("scripts/package-app.sh"),
            encoding: .utf8
        )

        #expect(script.contains(
            "cp -R \"$ROOT/.build/release/SVNMac_SVNMac.bundle\" "
                + "\"$APP/Contents/Resources/SVNMac_SVNMac.bundle\""
        ))
        let source = try repositorySource("AppSettings.swift")
        #expect(source.contains(
            "Bundle.main.url(forResource: \"SVNMac_SVNMac\", withExtension: \"bundle\")"
        ))
        #expect(source.contains("let resources = packagedResourceBundle ?? .module"))
    }

    @Test func customAboutWindowShowsDistributionCredit() throws {
        let source = try repositorySource("AppAboutView.swift")

        #expect(source.contains("Distributed by MR.DEVELLO"))
        #expect(source.contains("© 2026 Taehyun Kim"))
    }

    @Test func firstRunRepositorySheetExposesSampleProjectEntry() throws {
        let source = try repositorySource("RepositoryDialogs.swift")

        #expect(source.contains("\"ui.browse.sample.project.9ad211da\""))
        #expect(AppLanguage.korean.localized("ui.browse.sample.project.9ad211da") == "샘플 프로젝트 둘러보기")
        #expect(AppLanguage.english.localized("ui.browse.sample.project.9ad211da") == "Browse Sample Project")
        #expect(source.contains("onBrowseDemo()"))
    }

    @Test func supportedLanguagesExposeNativeDisplayNames() {
        #expect(AppLanguage.allCases.map(\.displayName) == ["한국어", "English"])
    }

    @Test func firstRunRepositorySheetExposesExtensibleLanguageMenu() throws {
        let source = try repositorySource("RepositoryDialogs.swift")

        #expect(source.contains("@AppStorage(AppSettings.languageKey)"))
        #expect(source.contains("ForEach(AppLanguage.allCases"))
        #expect(source.contains("appLanguage.localized(\"ui.language.8e5b78fb\")"))
        #expect(source.contains("systemImage: \"globe\""))
    }

    @Test func sampleEntryIsSecondaryAndPlacedWithTrailingActions() throws {
        let file = try repositorySource("RepositoryDialogs.swift")
        let viewStart = try #require(file.range(of: "struct AddRepositoryView: View"))
        let viewEnd = try #require(file.range(of: "struct CredentialsView: View"))
        let source = String(file[viewStart.lowerBound..<viewEnd.lowerBound])
        let register = try #require(source.range(of: "Button(appLanguage.localized(\"ui.register.existing.local.folder.fcf466c4\""))
        let sample = try #require(source.range(of: "Button(appLanguage.localized(\"ui.browse.sample.project.9ad211da\""))
        let cancel = try #require(source.range(of: "Button(appLanguage.localized(\"ui.cancel.a2ce2c22\""))
        let spacer = register.lowerBound < sample.lowerBound
            ? source.range(of: "Spacer()", range: register.upperBound..<sample.lowerBound)
            : nil

        #expect(register.lowerBound < sample.lowerBound)
        #expect(sample.lowerBound < cancel.lowerBound)
        #expect(spacer != nil)
    }

    @Test func demoExitUsesVisibleOrangeTextButton() throws {
        let source = try repositorySource("ContentView.swift")
        let start = try #require(source.range(of: "Button(appLanguage.localized(\"ui.exit.demo.3a329c52\"))"))
        let end = try #require(source.range(
            of: "Text(appLanguage.localized(\"ui.refresh.0aca6bd2\"))",
            range: start.upperBound..<source.endIndex
        ))
        let demoButton = String(source[start.lowerBound..<end.lowerBound])

        #expect(demoButton.contains(".buttonStyle(.borderedProminent)"))
        #expect(demoButton.contains(".tint(.orange)"))
        #expect(!demoButton.contains("systemImage:"))
    }

    @Test func exitingEnvironmentDemoReturnsToLiveStore() throws {
        let source = try repositorySource("SVNMacApp.swift")

        #expect(source.contains("_liveStore = State(initialValue: ProjectStore())"))
        #expect(source.contains("_demoStore = State(initialValue: ProjectStore.demo())"))
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
