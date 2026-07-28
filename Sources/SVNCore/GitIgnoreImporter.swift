import Foundation

public enum IgnoreImportDisposition: Hashable, Sendable {
    case alreadyApplied(SVNIgnoreRule)
    case proposal(SVNIgnoreRule, requiresConfirmation: Bool)
    case unsupported(reason: String)
    case conflict(reason: String)
}

public struct IgnoreImportItem: Identifiable, Hashable, Sendable {
    public let rule: GitIgnoreRule
    public let disposition: IgnoreImportDisposition
    public let warning: String?

    public var id: String { rule.id }

    public init(rule: GitIgnoreRule, disposition: IgnoreImportDisposition, warning: String? = nil) {
        self.rule = rule
        self.disposition = disposition
        self.warning = warning
    }

    public var proposal: SVNIgnoreRule? {
        if case let .proposal(rule, _) = disposition { return rule }
        return nil
    }

    public var isSelectable: Bool { proposal != nil }
}

public enum GitIgnoreImporter {
    public static func makePreview(
        rules: [GitIgnoreRule],
        existingRules: [SVNIgnoreRule],
        managedDirectories: Set<String>,
        trackedPaths: [String]
    ) -> [IgnoreImportItem] {
        rules.map {
            makePreviewItem(
                rule: $0,
                existingRules: existingRules,
                managedDirectories: managedDirectories,
                trackedPaths: trackedPaths
            )
        }
    }

    private static func makePreviewItem(
        rule: GitIgnoreRule,
        existingRules: [SVNIgnoreRule],
        managedDirectories: Set<String>,
        trackedPaths: [String]
    ) -> IgnoreImportItem {
        if rule.isNegated {
            return IgnoreImportItem(rule: rule, disposition: .unsupported(reason: "예외 규칙(!)은 SVN 무시 속성으로 안전하게 변환할 수 없습니다."))
        }
        if rule.pattern.contains("**") {
            return IgnoreImportItem(rule: rule, disposition: .unsupported(reason: "재귀 패턴(**)은 SVN 무시 속성과 의미가 다릅니다."))
        }

        let components = rule.pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else {
            return IgnoreImportItem(rule: rule, disposition: .unsupported(reason: "빈 패턴입니다."))
        }
        let parentComponents = Array(components.dropLast())
        guard !parentComponents.contains(where: containsGlob) else {
            return IgnoreImportItem(rule: rule, disposition: .unsupported(reason: "디렉터리 구간에 glob이 포함된 규칙은 변환할 수 없습니다."))
        }

        let sourceComponents = rule.sourceDirectory == "." ? [] : rule.sourceDirectory.split(separator: "/").map(String.init)
        let directoryComponents = sourceComponents + parentComponents
        let directory = directoryComponents.isEmpty ? "." : directoryComponents.joined(separator: "/")
        let pattern = components.last!
        let isGlobal = parentComponents.isEmpty && !rule.isRootAnchored
        let propertyKind: SVNIgnorePropertyKind = isGlobal ? .global : .local
        guard managedDirectories.contains(directory) else {
            return IgnoreImportItem(
                rule: rule,
                disposition: .conflict(reason: "SVN이 관리하는 속성 대상 디렉터리를 찾을 수 없습니다: \(directory)")
            )
        }

        let proposal = SVNIgnoreRule(
            directory: directory,
            pattern: pattern,
            propertyKind: propertyKind
        )
        if let existing = existingRules.first(where: {
            $0.directory == proposal.directory
                && $0.pattern == proposal.pattern
                && $0.propertyKind == proposal.propertyKind
        }) {
            return IgnoreImportItem(rule: rule, disposition: .alreadyApplied(existing))
        }

        let trackedMatches = trackedPaths.filter { matches(path: $0, rule: rule) }
        let warning = trackedMatches.isEmpty
            ? nil
            : "이미 추적 중인 \(trackedMatches.count)개 항목에는 무시 규칙이 적용되지 않습니다."
        return IgnoreImportItem(
            rule: rule,
            disposition: .proposal(proposal, requiresConfirmation: isGlobal),
            warning: warning
        )
    }

    private static func containsGlob(_ value: String) -> Bool {
        value.contains("*") || value.contains("?") || value.contains("[")
    }

    private static func matches(path: String, rule: GitIgnoreRule) -> Bool {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let scopePrefix = rule.sourceDirectory == "." ? "" : rule.sourceDirectory + "/"
        guard scopePrefix.isEmpty || normalized == rule.sourceDirectory || normalized.hasPrefix(scopePrefix) else {
            return false
        }
        let relative = scopePrefix.isEmpty ? normalized : String(normalized.dropFirst(scopePrefix.count))
        if rule.isRootAnchored || rule.pattern.contains("/") {
            return relative == rule.pattern || relative.hasPrefix(rule.pattern + "/")
        }
        let name = (relative as NSString).lastPathComponent
        if rule.pattern.hasPrefix("*.") {
            return name.hasSuffix(String(rule.pattern.dropFirst()))
        }
        return name == rule.pattern
    }
}
