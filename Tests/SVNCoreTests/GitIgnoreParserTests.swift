import Testing
@testable import SVNCore

@Test func parsesGitIgnoreSyntaxWithoutDroppingSourceMeaning() {
    let rules = GitIgnoreParser.parse("""
    # comment
    *.log
    /build/
    !keep.log
    \\#literal
    name\\ with\\ spaces
    nested/cache/
    """)

    #expect(rules.map(\.sourceLine) == [2, 3, 4, 5, 6, 7])
    #expect(rules[0].pattern == "*.log")
    #expect(rules[1].pattern == "build")
    #expect(rules[1].isRootAnchored)
    #expect(rules[1].isDirectoryOnly)
    #expect(rules[2].isNegated)
    #expect(rules[3].pattern == "#literal")
    #expect(rules[4].pattern == "name with spaces")
    #expect(rules[5].pattern == "nested/cache")
    #expect(rules[5].isDirectoryOnly)
}

@Test func keepsEscapedTrailingSpaceAndDropsUnescapedTrailingSpace() {
    let rules = GitIgnoreParser.parse("plain   \nkept\\ \n")

    #expect(rules.map(\.pattern) == ["plain", "kept "])
}
