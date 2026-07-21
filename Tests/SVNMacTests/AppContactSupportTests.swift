import Foundation
import Testing
@testable import SVNMac

@Suite("AppContactSupportTests")
struct AppContactSupportTests {
    @Test func supportDetailsUseRequestedEmailAddress() {
        #expect(AppContactSupport.email == "thkim@mrdevello.com")
        #expect(AppContactSupport.mailURL.absoluteString == "mailto:thkim@mrdevello.com")
    }

    @Test func localizedHelpMessagesExposeEmailAddress() {
        #expect(AppContactSupport.message(for: .korean).contains(AppContactSupport.email))
        #expect(AppContactSupport.message(for: .english).contains(AppContactSupport.email))
    }

    @Test func appInformationCreditsExposeEmailAddress() throws {
        let credits = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Resources/Credits.rtf"),
            encoding: .utf8
        )

        #expect(credits.contains(AppContactSupport.email))
    }

    @Test func appWiresHelpMenuToSupportAlert() throws {
        let appSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/SVNMac/SVNMacApp.swift"),
            encoding: .utf8
        )

        #expect(appSource.contains("CommandGroup(replacing: .help)"))
        #expect(appSource.contains("AppContactSupport.alertTitle(for: appLanguage)"))
        #expect(appSource.contains("NSWorkspace.shared.open(AppContactSupport.mailURL)"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
