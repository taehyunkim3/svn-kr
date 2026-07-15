import Foundation

public enum SVNXMLParser {
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
}

private final class StatusDelegate: NSObject, XMLParserDelegate {
    var entries: [SVNStatusEntry] = []
    private var path: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "entry" {
            path = attributeDict["path"]
        } else if elementName == "wc-status", let path {
            let item = attributeDict["item"] ?? "unknown"
            if item != "normal" && item != "external" {
                entries.append(SVNStatusEntry(path: path, item: item, revision: attributeDict["revision"]))
            }
        }
    }
}

private final class LogDelegate: NSObject, XMLParserDelegate {
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
        case "date": date = ISO8601DateFormatter().date(from: text)
        case "msg": message = text
        case "path":
            if let attributes = pathAttributes {
                changedPaths.append(SVNChangedPath(
                    path: text,
                    action: attributes["action"] ?? "?",
                    kind: attributes["kind"],
                    copyFromPath: attributes["copyfrom-path"],
                    copyFromRevision: attributes["copyfrom-rev"],
                    textModified: attributes["text-mods"],
                    propertiesModified: attributes["prop-mods"]
                ))
            }
            pathAttributes = nil
        case "property":
            if let propertyName {
                revisionProperties.append(SVNRevisionProperty(name: propertyName, value: text))
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
}
