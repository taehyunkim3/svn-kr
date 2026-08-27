import Foundation
import Testing
@testable import SVNCore

@Test func svnmuccExecutablePrefersInjectedPath() async {
    let injectedPath = "/test/bin/svnmucc"
    let client = SVNClient(
        svnmuccExecutablePath: injectedPath,
        executableFileChecker: { path in
            path == injectedPath || path == "/opt/homebrew/bin/svnmucc"
        }
    )

    let executableURL = await client.svnmuccExecutableURL()

    #expect(executableURL?.path == injectedPath)
}

@Test func missingSVNMuccExecutableReturnsNil() async {
    let client = SVNClient(executableFileChecker: { _ in false })

    #expect(await client.svnmuccExecutableURL() == nil)
}
