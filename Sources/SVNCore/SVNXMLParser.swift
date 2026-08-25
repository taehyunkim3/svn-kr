import Foundation

public enum SVNXMLParser {
    static func repositoryListEntries(from data: Data) throws -> [SVNRepositoryListEntry] {
        let delegate = RepositoryListDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.entries
    }

    /// 로컬 작업 복사본의 변경 항목만 읽습니다. 변경 없는 정상 항목과 external은
    /// UI에 표시할 필요가 없으므로 파싱 단계에서 제거합니다.
    public static func statuses(from data: Data) throws -> [SVNStatusEntry] {
        let delegate = StatusDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        let conflictedCanonicalPaths = Set(
            delegate.entries
                .filter { $0.item == .conflicted }
                .map { $0.path.precomposedStringWithCanonicalMapping }
        )
        return delegate.entries.filter { entry in
            !isConflictArtifact(entry.path, for: conflictedCanonicalPaths)
        }
    }

    private static func isConflictArtifact(
        _ path: String,
        for conflictedCanonicalPaths: Set<String>
    ) -> Bool {
        let basePath: String
        if path.hasSuffix(".mine") {
            basePath = String(path.dropLast(".mine".count))
        } else if let revisionSuffix = path.range(of: #"\.r[0-9]+$"#, options: .regularExpression) {
            basePath = String(path[..<revisionSuffix.lowerBound])
        } else {
            return false
        }
        return conflictedCanonicalPaths.contains(basePath.precomposedStringWithCanonicalMapping)
    }

    /// 전체 파일 탐색용으로 정상 항목을 포함한 작업 복사본 경로를 읽습니다.
    public static func workingCopyEntries(from data: Data) throws -> [SVNWorkingCopyEntry] {
        let delegate = WorkingCopyEntriesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.entries
    }

    /// 한 번의 verbose status 응답에서 변경 목록, 리비전 범위와 정규화 충돌을
    /// 함께 계산해 서로 다른 시점의 SVN 상태가 섞이지 않게 합니다.
    public static func workingCopySnapshot(from data: Data) throws -> SVNWorkingCopySnapshot {
        try SVNWorkingCopySnapshot(entries: workingCopyEntries(from: data))
    }

    /// 전체 버전 관리 항목의 기준 리비전 범위를 계산합니다.
    /// 미추적·무시 항목처럼 리비전이 없는 경로는 범위에서 제외합니다.
    public static func workingCopyRevision(from data: Data) throws -> SVNWorkingCopyRevision {
        let entries = try workingCopyEntries(from: data)
        let revisions = entries.compactMap(\.revision).compactMap(Int.init).filter { $0 >= 0 }
        guard let minimum = revisions.min(), let maximum = revisions.max() else {
            throw SVNError.malformedResponse
        }
        return SVNWorkingCopyRevision(minimum: String(minimum), maximum: String(maximum))
    }

    public static func logs(from data: Data) throws -> [SVNLogEntry] {
        let delegate = LogDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.entries
    }

    public static func workingCopyIsOutOfDate(from data: Data) throws -> Bool {
        let delegate = RemoteStatusDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.hasRemoteChanges
    }

    public static func remoteChanges(from data: Data) throws -> [SVNStatusEntry] {
        let delegate = RemoteChangesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.entries
    }

    public static func ignoreRules(from data: Data) throws -> [SVNIgnoreRule] {
        let delegate = IgnoreRulesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.rules
    }

    public static func repositoryLocks(fromStatus data: Data) throws -> [SVNLockInfo] {
        let delegate = StatusLocksDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.locks
    }

    public static func repositoryLock(fromInfo data: Data) throws -> SVNLockInfo? {
        let delegate = InfoLockDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.lock
    }

    public static func conflictDetails(fromInfo data: Data) throws -> SVNConflictDetails? {
        let delegate = ConflictInfoDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.details
    }
}

private final class RepositoryListDelegate: NSObject, XMLParserDelegate {
    var entries: [SVNRepositoryListEntry] = []
    private var isDirectory = false
    private var name: String?
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        if elementName == "entry" {
            isDirectory = attributeDict["kind"] == "dir"
            name = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "name" {
            name = text
        } else if elementName == "entry", let name {
            entries.append(SVNRepositoryListEntry(path: name, isDirectory: isDirectory))
            self.name = nil
        }
        text = ""
    }
}

private final class ConflictInfoDelegate: NSObject, XMLParserDelegate {
    var details: SVNConflictDetails?
    private var entryPath = ""
    private var type = "unknown"
    private var operation = "unknown"
    private var previousBaseFile: String?
    private var myFile: String?
    private var serverFile: String?
    private var previousRevision: String?
    private var serverRevision: String?
    private var treeConflictAction: String?
    private var treeConflictReason: String?
    private var treeConflictKind: String?
    private var inConflict = false
    private var conflictRootElementName = ""
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "entry" { entryPath = attributeDict["path"] ?? "" }
        if elementName == "conflict" || elementName == "tree-conflict" {
            if !inConflict {
                inConflict = true
                conflictRootElementName = elementName
                type = elementName == "tree-conflict" ? "tree" : (attributeDict["type"] ?? "unknown")
                operation = attributeDict["operation"] ?? "unknown"
            } else if elementName == "tree-conflict" {
                type = "tree"
                operation = attributeDict["operation"] ?? operation
            }
            if elementName == "tree-conflict" {
                treeConflictAction = attributeDict["action"]
                treeConflictReason = attributeDict["reason"]
                treeConflictKind = attributeDict["kind"]
            }
        } else if elementName == "version", inConflict {
            if attributeDict["side"] == "source-left" { previousRevision = attributeDict["revision"] }
            if attributeDict["side"] == "source-right" { serverRevision = attributeDict["revision"] }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard inConflict else { return }
        switch elementName {
        case "prev-base-file": previousBaseFile = text
        case "prev-wc-file": myFile = text
        case "cur-base-file": serverFile = text
        case conflictRootElementName:
            details = SVNConflictDetails(
                path: entryPath,
                type: type,
                operation: operation,
                previousBaseFile: previousBaseFile,
                myFile: myFile,
                serverFile: serverFile,
                previousRevision: previousRevision,
                serverRevision: serverRevision,
                treeConflictAction: type == "tree" ? treeConflictAction : nil,
                treeConflictReason: type == "tree" ? treeConflictReason : nil,
                treeConflictKind: type == "tree" ? treeConflictKind : nil
            )
            inConflict = false
            conflictRootElementName = ""
        default: break
        }
        text = ""
    }
}

private final class StatusLocksDelegate: NSObject, XMLParserDelegate {
    var locks: [SVNLockInfo] = []
    private var entryPath = ""
    private var inRepositoryStatus = false
    private var lockBuilder: LockBuilder?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "entry" { entryPath = attributeDict["path"] ?? "" }
        if elementName == "repos-status" { inRepositoryStatus = true }
        if elementName == "lock", inRepositoryStatus { lockBuilder = LockBuilder(path: entryPath) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        lockBuilder?.set(element: elementName, value: text)
        if elementName == "lock", let lockBuilder {
            locks.append(lockBuilder.build())
            self.lockBuilder = nil
        }
        if elementName == "repos-status" { inRepositoryStatus = false }
        text = ""
    }
}

private final class InfoLockDelegate: NSObject, XMLParserDelegate {
    var lock: SVNLockInfo?
    private var entryPath = ""
    private var lockBuilder: LockBuilder?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "entry" { entryPath = attributeDict["path"] ?? "" }
        if elementName == "lock" { lockBuilder = LockBuilder(path: entryPath) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        lockBuilder?.set(element: elementName, value: text)
        if elementName == "lock", let lockBuilder {
            lock = lockBuilder.build()
            self.lockBuilder = nil
        }
        text = ""
    }
}

private final class LockBuilder {
    let path: String
    var token: String?
    var owner = ""
    var comment: String?
    var created: Date?
    private let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let dateFormatter = ISO8601DateFormatter()

    init(path: String) { self.path = path }

    func set(element: String, value: String) {
        switch element {
        case "token": token = value
        case "owner": owner = value
        case "comment": comment = value
        case "created":
            created = fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
        default: break
        }
    }

    func build() -> SVNLockInfo {
        SVNLockInfo(path: path, token: token, owner: owner, comment: comment, created: created)
    }
}

/// SVN ignore 속성의 `propget --xml` 결과를 디렉터리별 패턴으로 펼칩니다.
private final class IgnoreRulesDelegate: NSObject, XMLParserDelegate {
    var rules: [SVNIgnoreRule] = []
    private var targetPath: String?
    private var propertyKind: SVNIgnorePropertyKind?
    private var isInheritedProperty = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "target" { targetPath = attributeDict["path"] }
        if elementName == "property" || elementName == "inherited_property" {
            propertyKind = switch attributeDict["name"] {
            case "svn:ignore": .local
            case "svn:global-ignores": .global
            default: nil
            }
            isInheritedProperty = elementName == "inherited_property"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if (elementName == "property" || elementName == "inherited_property"),
           let propertyKind,
           let targetPath {
            rules += text.split(whereSeparator: \.isNewline).map {
                SVNIgnoreRule(
                    directory: isInheritedProperty ? "." : targetPath,
                    pattern: String($0),
                    propertyKind: propertyKind,
                    inheritedFrom: isInheritedProperty ? targetPath : nil
                )
            }
            self.propertyKind = nil
            isInheritedProperty = false
        } else if elementName == "target" {
            targetPath = nil
        }
        text = ""
    }
}

/// `svn status --xml`에서 각 entry의 로컬 상태만 수집합니다.
private final class StatusDelegate: NSObject, XMLParserDelegate {
    var entries: [SVNStatusEntry] = []
    private var path: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "entry" {
            path = attributeDict["path"]
        } else if elementName == "wc-status", let path {
            let rawItem = attributeDict["item"] ?? "unknown"
            let propertyState = SVNPropertyState(
                rawValue: attributeDict["props"] ?? "none"
            ) ?? .none
            let isSwitched = attributeDict["switched"] == "true"
            guard rawItem != "external" else { return }
            guard rawItem != "normal" || propertyState != .none || isSwitched else { return }
            entries.append(SVNStatusEntry(
                path: path,
                item: SVNStatusKind(rawValue: rawItem),
                revision: attributeDict["revision"],
                propertyState: propertyState,
                isSwitched: isSwitched
            ))
        }
    }
}

private final class WorkingCopyEntriesDelegate: NSObject, XMLParserDelegate {
    var entries: [SVNWorkingCopyEntry] = []
    private var path: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "entry" {
            path = attributeDict["path"]
        } else if elementName == "wc-status", let path {
            entries.append(SVNWorkingCopyEntry(
                path: path,
                status: attributeDict["item"] ?? "unknown",
                revision: attributeDict["revision"],
                treeConflicted: attributeDict["tree-conflicted"] == "true"
            ))
        }
    }
}

/// `svn status --show-updates --xml`의 repos-status를 보고 서버 변경 유무만 판단합니다.
private final class RemoteStatusDelegate: NSObject, XMLParserDelegate {
    var hasRemoteChanges = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "repos-status" else { return }
        let item = attributeDict["item"] ?? "none"
        let properties = attributeDict["props"] ?? "none"
        if item != "none" || properties != "none" {
            hasRemoteChanges = true
        }
    }
}

private final class RemoteChangesDelegate: NSObject, XMLParserDelegate {
    var entries: [SVNStatusEntry] = []
    private var path: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "entry" {
            path = attributeDict["path"]
        } else if elementName == "repos-status", let path {
            let item = attributeDict["item"] ?? "none"
            let properties = attributeDict["props"] ?? "none"
            guard item != "none" || properties != "none" else { return }
            entries.append(SVNStatusEntry(
                path: path,
                item: SVNStatusKind(rawValue: item == "none" ? "modified" : item),
                revision: nil
            ))
        }
    }
}

/// logentry 안의 작성자, 날짜, 메시지, 경로, 사용자 정의 속성을 한 모델로 조립합니다.
private final class LogDelegate: NSObject, XMLParserDelegate {
    // XMLParser는 텍스트를 여러 번 나누어 전달할 수 있으므로 foundCharacters에서
    // 누적하고, 닫는 태그를 만났을 때 현재 모델 속성으로 확정합니다.
    var entries: [SVNLogEntry] = []
    private var revision = ""
    private var author = ""
    private var date: Date?
    private var message = ""
    private var originalMessage: String?
    private var changedPaths: [SVNChangedPath] = []
    private var revisionProperties: [SVNRevisionProperty] = []
    private var pathAttributes: [String: String]?
    private var propertyName: String?
    private var text = ""
    private let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let dateFormatter = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "logentry" {
            revision = attributeDict["revision"] ?? ""
            author = ""
            date = nil
            message = ""
            originalMessage = nil
            changedPaths = []
            revisionProperties = []
        } else if elementName == "path" {
            pathAttributes = attributeDict
        } else if elementName == "property" {
            propertyName = attributeDict["name"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "author": author = text
        case "date": date = parseDate(text)
        case "msg": setMessage(text)
        case "path":
            if let attributes = pathAttributes {
                changedPaths.append(SVNChangedPath(
                    path: text,
                    action: SVNChangeAction(rawValue: attributes["action"] ?? "?"),
                    kind: attributes["kind"].map(SVNNodeKind.init(rawValue:)),
                    copyFromPath: attributes["copyfrom-path"],
                    copyFromRevision: attributes["copyfrom-rev"],
                    textModified: attributes["text-mods"].map { $0 == "true" },
                    propertiesModified: attributes["prop-mods"].map { $0 == "true" }
                ))
            }
            pathAttributes = nil
        case "property":
            if let propertyName {
                switch propertyName {
                case "svn:author": author = text
                case "svn:date": date = parseDate(text)
                case "svn:log": setMessage(text)
                default: revisionProperties.append(SVNRevisionProperty(name: propertyName, value: text))
                }
            }
            propertyName = nil
        case "logentry":
            let email = revisionProperties.first { property in
                let name = property.name.lowercased()
                return name == "email" || name == "author-email" || name == "author_email" || name == "svn:author-email"
            }?.value
            entries.append(SVNLogEntry(
                revision: revision,
                author: author,
                email: email,
                date: date,
                message: message,
                originalMessage: originalMessage,
                changedPaths: changedPaths,
                revisionProperties: revisionProperties
            ))
        default: break
        }
        text = ""
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
    }

    private func setMessage(_ value: String) {
        if let repaired = value.repairedLegacyUTF8Mojibake {
            message = repaired
            originalMessage = value
        } else {
            message = value
            originalMessage = nil
        }
    }
}

private extension String {
    /// UTF-8 한글 바이트를 Latin-1 문자로 잘못 저장한 과거 SVN 로그를 표시할 때 복원합니다.
    /// 정상 한글이나 일반 라틴 문장은 변경하지 않고, 복원 결과에 한글이 있을 때만 적용합니다.
    var repairedLegacyUTF8Mojibake: String? {
        let scalars = unicodeScalars
        guard !scalars.isEmpty, scalars.allSatisfy({ $0.value <= 0xFF }) else { return nil }
        let bytes = scalars.map { UInt8($0.value) }
        guard let decoded = String(data: Data(bytes), encoding: .utf8) else { return nil }
        let normalized = decoded.precomposedStringWithCanonicalMapping
        guard normalized.unicodeScalars.contains(where: { scalar in
            (0x1100...0x11FF).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }) else { return nil }
        return normalized
    }
}
