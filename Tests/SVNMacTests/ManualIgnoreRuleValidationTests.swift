import SVNCore
import Testing
@testable import SVNMac

@Test func manualIgnoreRuleValidationRejectsEmptyPattern() {
    #expect(throws: ManualIgnoreRuleValidationError.emptyPattern) {
        try ManualIgnoreRuleValidation.validate(
            pattern: "   ",
            directory: ".",
            propertyKind: .local,
            existingRules: []
        )
    }
}

@Test func manualIgnoreRuleValidationRejectsPatternContainingSlash() {
    #expect(throws: ManualIgnoreRuleValidationError.invalidPattern) {
        try ManualIgnoreRuleValidation.validate(
            pattern: "logs/*.log",
            directory: ".",
            propertyKind: .local,
            existingRules: []
        )
    }
}

@Test func manualIgnoreRuleValidationRejectsDuplicateRule() {
    let existingRule = SVNIgnoreRule(
        directory: "logs",
        pattern: "*.log",
        propertyKind: .global
    )

    #expect(throws: ManualIgnoreRuleValidationError.duplicateRule) {
        try ManualIgnoreRuleValidation.validate(
            pattern: "*.log",
            directory: "logs",
            propertyKind: .global,
            existingRules: [existingRule]
        )
    }
}

@Test func manualIgnoreRuleValidationNormalizesBlankDirectoryToRoot() throws {
    let input = try ManualIgnoreRuleValidation.validate(
        pattern: "*.log",
        directory: "   ",
        propertyKind: .local,
        existingRules: []
    )

    #expect(input.directory == ".")
}

@Test func manualIgnoreRuleValidationTrimsValidInput() throws {
    let input = try ManualIgnoreRuleValidation.validate(
        pattern: "  *.log  ",
        directory: "  logs  ",
        propertyKind: .global,
        existingRules: []
    )

    #expect(input == ManualIgnoreRuleInput(
        pattern: "*.log",
        directory: "logs",
        propertyKind: .global
    ))
}
