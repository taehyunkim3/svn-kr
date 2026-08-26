import Testing
@testable import SVNCore

@Test func convertsSafeGitRulesAndExplainsUnsupportedRules() {
    let rules = GitIgnoreParser.parse("""
    *.log
    /build/
    nested/cache/
    !keep.log
    **/generated
    """)
    let preview = GitIgnoreImporter.makePreview(
        rules: rules,
        existingRules: [],
        managedDirectories: [".", "nested"],
        trackedPaths: ["Sources/app.log", "nested/keep.swift"]
    )

    #expect(preview[0].proposal == SVNIgnoreRule(
        directory: ".",
        pattern: "*.log",
        propertyKind: .global
    ))
    #expect(preview[0].warning != nil)
    #expect(preview[1].proposal == SVNIgnoreRule(
        directory: ".",
        pattern: "build",
        propertyKind: .local
    ))
    #expect(preview[1].warning?.contains("같은 이름의 파일") == true)
    #expect(preview[2].proposal == SVNIgnoreRule(
        directory: "nested",
        pattern: "cache",
        propertyKind: .local
    ))
    #expect(preview[2].warning?.contains("같은 이름의 파일") == true)
    if case .unsupported = preview[3].disposition {} else {
        Issue.record("Negated rule must remain unsupported")
    }
    if case .unsupported = preview[4].disposition {} else {
        Issue.record("Recursive rule must remain unsupported")
    }
}

@Test func marksExistingRulesAndUnmanagedDirectories() {
    let existing = SVNIgnoreRule(directory: ".", pattern: ".DS_Store", propertyKind: .global)
    let preview = GitIgnoreImporter.makePreview(
        rules: GitIgnoreParser.parse(".DS_Store\nmissing/cache\n"),
        existingRules: [existing],
        managedDirectories: ["."],
        trackedPaths: []
    )

    #expect(preview[0].disposition == .alreadyApplied(existing))
    if case .conflict = preview[1].disposition {} else {
        Issue.record("Unmanaged directory must remain a conflict")
    }
    #expect(!preview[0].isSelectable)
    #expect(!preview[1].isSelectable)
}

@Test func resolvesRulesFromNestedGitIgnoreRelativeToTheirOwnDirectory() {
    let rootRules = GitIgnoreParser.parse("*.log\n")
    let nestedRules = GitIgnoreParser.parse("/local.txt\nbuild/\ncache/tmp\n", sourceDirectory: "lib")
    let preview = GitIgnoreImporter.makePreview(
        rules: rootRules + nestedRules,
        existingRules: [],
        managedDirectories: [".", "lib", "lib/cache"],
        trackedPaths: ["lib/build"]
    )

    #expect(preview[0].proposal == SVNIgnoreRule(directory: ".", pattern: "*.log", propertyKind: .global))
    #expect(preview[1].proposal == SVNIgnoreRule(directory: "lib", pattern: "local.txt", propertyKind: .local))
    #expect(preview[2].proposal == SVNIgnoreRule(directory: "lib", pattern: "build", propertyKind: .global))
    #expect(preview[2].warning?.contains("같은 이름의 파일") == true)
    #expect(preview[2].warning?.contains("이미 추적 중인 1개") == true)
    #expect(preview[3].proposal == SVNIgnoreRule(directory: "lib/cache", pattern: "tmp", propertyKind: .local))
}
