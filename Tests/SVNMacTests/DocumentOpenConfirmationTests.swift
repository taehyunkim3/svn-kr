import Foundation
import Testing
@testable import SVNMac

@Test func documentOpenPromptUsesASheetWithAnOpenWithoutLockOnlyCheckbox() throws {
    let sources = try svnMacSources()
    let confirmation = try source(named: "DocumentOpenConfirmation.swift", in: sources)

    #expect(confirmation.contains("content.sheet(item: $store.documentOpenRequest)"))
    #expect(!confirmation.contains("confirmationDialog("))
    #expect(confirmation.contains("@State private var remembersOpenWithoutLock = false"))
    #expect(confirmation.contains(".ui.localizationOpen.withoutLockAndDoNotAskAgain"))
    #expect(confirmation.contains("rememberingChoice: remembersOpenWithoutLock"))
    #expect(confirmation.contains("Task { await store.lockAndOpen(request) }"))
    #expect(confirmation.contains("if request.existingLock == nil"))
    #expect(confirmation.contains("lock.owner"))
    #expect(confirmation.contains("if request.lockInformationWasUnavailable"))
}

@Test func documentOpenSettingsOfferThreePoliciesAndConditionTheWarning() throws {
    let sources = try svnMacSources()
    let settings = try source(named: "AppSettings.swift", in: sources)

    #expect(settings.contains("@AppStorage(AppSettings.documentOpenLockPolicyKey)"))
    #expect(settings.contains(".tag(DocumentOpenLockPolicy.askEveryTime.rawValue)"))
    #expect(settings.contains(".tag(DocumentOpenLockPolicy.alwaysOpenWithoutLock.rawValue)"))
    #expect(settings.contains(".tag(DocumentOpenLockPolicy.alwaysLockAndOpen.rawValue)"))
    #expect(settings.contains("if documentOpenLockPolicy == .alwaysLockAndOpen"))
    #expect(settings.contains("systemImage: \"exclamationmark.triangle.fill\""))
    #expect(settings.contains(".foregroundStyle(.orange)"))
    #expect(settings.contains(".ui.locked.filesBlockOtherUsersUntilCommitOrUnl"))
}

@Test func documentOpenPolicyStringsExistInEveryLocalizationResource() throws {
    let keys = [
        "ui.always.lock.and.open.documents.2f9a7c11",
        "ui.always.open.documents.without.locking.8b6e42d0",
        "ui.ask.every.time.before.opening.documents.31c4d8a2",
        "ui.document.opening.method.9d73be41",
        "ui.locked.files.block.other.users.until.commit.or.unl.6a2e91bf",
        "ui.open.without.lock.and.do.not.ask.again.4c6f8a20",
    ]
    let resources = try svnMacSources().appendingPathComponent("Resources", isDirectory: true)
    let localizationFiles = [
        resources.appendingPathComponent("Localizable.xcstrings"),
        resources.appendingPathComponent("ko.lproj/Localizable.strings"),
        resources.appendingPathComponent("en.lproj/Localizable.strings"),
    ]

    for file in localizationFiles {
        let contents = try String(contentsOf: file, encoding: .utf8)
        for key in keys {
            #expect(contents.contains(key), "\(key) is missing from \(file.path)")
        }
    }

    #expect(
        AppLanguage.korean.localized(
            .ui.locked.filesBlockOtherUsersUntilCommitOrUnl
        ) == "잠긴 파일은 커밋하거나 잠금 목록에서 해제하기 전까지 다른 사람이 그 파일을 수정할 수 없습니다."
    )
}

private func svnMacSources() throws -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SVNMac", isDirectory: true)
}

private func source(named name: String, in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}
