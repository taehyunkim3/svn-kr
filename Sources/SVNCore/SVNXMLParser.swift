import Foundation

public enum SVNXMLParser {
    /// 로컬 작업 복사본의 변경 항목만 읽습니다. 정상 항목과 external은 UI에
    /// 표시할 필요가 없으므로 파싱 단계에서 제거합니다.
    public static func statuses(from data: Data) throws -> [SVNStatusEntry] {
        let delegate = StatusDelegate()
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
        case "msg": message = text
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
                case "svn:log": message = text
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
