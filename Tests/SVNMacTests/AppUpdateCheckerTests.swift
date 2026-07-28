import Foundation
import Testing
@testable import SVNMac

@Suite("AppUpdateCheckerTests")
struct AppUpdateCheckerTests {
    @Test func comparesDottedVersionsNumerically() {
        #expect(AppUpdateService.isVersion("0.5.14", newerThan: "0.5.13"))
        #expect(AppUpdateService.isVersion("0.10.0", newerThan: "0.9.9"))
        #expect(!AppUpdateService.isVersion("0.5.13", newerThan: "0.5.13"))
        #expect(!AppUpdateService.isVersion("0.5.13.0", newerThan: "0.5.13"))
        #expect(!AppUpdateService.isVersion("0.5.12", newerThan: "0.5.13"))
    }

    @Test func lookupUsesBundleIdentifierAndCurrentRegion() throws {
        let service = AppUpdateService(
            bundleIdentifier: "com.mrdevello.svnmac",
            currentVersion: "0.5.13",
            regionCode: "KR"
        )
        let lookupURL = try #require(service.lookupURL)
        let components = try #require(URLComponents(url: lookupURL, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)

        #expect(components.host == "itunes.apple.com")
        #expect(queryItems.contains(URLQueryItem(name: "bundleId", value: "com.mrdevello.svnmac")))
        #expect(queryItems.contains(URLQueryItem(name: "country", value: "kr")))
    }

    @Test func appWiresCustomAboutWindowAndManualUpdateCommand() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/SVNMac/SVNMacApp.swift"),
            encoding: .utf8
        )
        let about = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/SVNMac/AppAboutView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("checkAutomaticallyIfNeeded()"))
        #expect(source.contains("Window(appLanguage.localized(\"ui.about.svn.kr.ddc63e52\""))
        #expect(about.contains("CommandGroup(replacing: .appInfo)"))
        #expect(about.contains("\"ui.check.for.updates.d0ccb7fe\""))
        #expect(about.contains("\"ui.view.in.app.store.7c79e972\""))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
