import Foundation

public enum SVNXMLParser {
    /// 로컬 작업 복사본의 변경 항목만 읽습니다. 정상 항목과 external은 UI에
    /// 표시할 필요가 없으므로 파싱 단계에서 제거합니다.
    public static func statuses(from data: Data) throws -> [SVNStatusEntry] {
        let delegate = StatusDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        let conflictedPaths = delegate.entries.filter { $0.item == .conflicted }.map(\.path)
        return delegate.entries.filter { entry in
            !conflictedPaths.contains { conflictedPath in
                entry.path == conflictedPath + ".mine" || entry.path.range(
                    of: "^\(NSRegularExpression.escapedPattern(for: conflictedPath))\\.r[0-9]+$",
                    options: .regularExpression
                ) != nil
            }
        }
    }

    /// 전체 파일 탐색용으로 정상 항목을 포함한 작업 복사본 경로를 읽습니다.
    public static func workingCopyEntries(from data: Data) throws -> [SVNWorkingCopyEntry] {
        let delegate = WorkingCopyEntriesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.entries
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
    private var inConflict = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "entry" { entryPath = attributeDict["path"] ?? "" }
        if elementName == "conflict" {
            inConflict = true
            type = attributeDict["type"] ?? "unknown"
            operation = attributeDict["operation"] ?? "unknown"
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
        case "conflict":
            details = SVNConflictDetails(
                path: entryPath,
                type: type,
                operation: operation,
                previousBaseFile: previousBaseFile,
                myFile: myFile,
                serverFile: serverFile,
                previousRevision: previousRevision,
                serverRevision: serverRevision
            )
            inConflict = false
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
    private let dateFormatter = ISO8601DateFormatter()

    init(path: String) { self.path = path }

    func set(element: String, value: String) {
        switch element {
        case "token": token = value
        case "owner": owner = value
        case "comment": comment = value
        case "created": created = dateFormatter.date(from: value)
        default: break
        }
    }

    func build() -> SVNLockInfo {
        SVNLockInfo(path: path, token: token, owner: owner, comment: comment, created: created)
    }
}

/// `svn propget svn:ignore --recursive --xml` 결과를 디렉터리별 패턴으로 펼칩니다.
private final class IgnoreRulesDelegate: NSObject, XMLParserDelegate {
    var rules: [SVNIgnoreRule] = []
    private var targetPath: String?
    private var isIgnoreProperty = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "target" { targetPath = attributeDict["path"] }
        if elementName == "property" { isIgnoreProperty = attributeDict["name"] == "svn:ignore" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "property", isIgnoreProperty, let targetPath {
            rules += text.split(whereSeparator: \.isNewline).map {
                SVNIgnoreRule(directory: targetPath, pattern: String($0))
            }
            isIgnoreProperty = false
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
            if rawItem != "normal" && rawItem != "external" {
                entries.append(SVNStatusEntry(
                    path: path,
                    item: SVNStatusKind(rawValue: rawItem),
                    revision: attributeDict["revision"]
                ))
            }
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
                revision: attributeDict["revision"]
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
        case "msg": message = text.repairingLegacyUTF8Mojibake
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
                case "svn:log": message = text.repairingLegacyUTF8Mojibake
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
}

private extension String {
    /// UTF-8 한글 바이트를 Latin-1 문자로 잘못 저장한 과거 SVN 로그를 표시할 때 복원합니다.
    /// 정상 한글이나 일반 라틴 문장은 변경하지 않고, 복원 결과에 한글이 있을 때만 적용합니다.
    var repairingLegacyUTF8Mojibake: String {
        let scalars = unicodeScalars
        guard !scalars.isEmpty, scalars.allSatisfy({ $0.value <= 0xFF }) else { return self }
        let bytes = scalars.map { UInt8($0.value) }
        guard let decoded = String(data: Data(bytes), encoding: .utf8) else { return self }
        let normalized = decoded.precomposedStringWithCanonicalMapping
        guard normalized.unicodeScalars.contains(where: { scalar in
            (0x1100...0x11FF).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }) else { return self }
        return normalized
    }
}
