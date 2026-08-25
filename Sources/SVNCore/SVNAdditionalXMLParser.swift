import Foundation

enum SVNAdditionalXMLParser {
    static func properties(from data: Data) throws -> [SVNProperty] {
        let delegate = PropertyListDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.properties
    }

    static func logs(from data: Data) throws -> [SVNLogEntry] {
        let delegate = IncomingLogDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SVNError.malformedResponse }
        return delegate.entries
    }
}

private final class PropertyListDelegate: NSObject, XMLParserDelegate {
    var properties: [SVNProperty] = []
    private var propertyName: String?
    private var propertyEncoding: String?
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "property" else { return }
        propertyName = attributeDict["name"]
        propertyEncoding = attributeDict["encoding"]
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard propertyName != nil else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "property", let propertyName else { return }
        let value: Data?
        if propertyEncoding == "base64" {
            value = Data(base64Encoded: text, options: .ignoreUnknownCharacters)
        } else {
            value = Data(text.utf8)
        }
        if let value {
            properties.append(SVNProperty(name: propertyName, value: value))
        } else {
            parser.abortParsing()
        }
        self.propertyName = nil
        propertyEncoding = nil
        text = ""
    }
}

private final class IncomingLogDelegate: NSObject, XMLParserDelegate {
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

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        switch elementName {
        case "logentry":
            revision = attributeDict["revision"] ?? ""
            author = ""
            date = nil
            message = ""
            changedPaths = []
            revisionProperties = []
        case "path":
            pathAttributes = attributeDict
        case "property":
            propertyName = attributeDict["name"]
        default:
            break
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
        switch elementName {
        case "author":
            author = text
        case "date":
            date = fractionalDateFormatter.date(from: text) ?? dateFormatter.date(from: text)
        case "msg":
            message = text
        case "path":
            if let pathAttributes {
                changedPaths.append(SVNChangedPath(
                    path: text,
                    action: SVNChangeAction(rawValue: pathAttributes["action"] ?? "?"),
                    kind: pathAttributes["kind"].map(SVNNodeKind.init(rawValue:)),
                    copyFromPath: pathAttributes["copyfrom-path"],
                    copyFromRevision: pathAttributes["copyfrom-rev"],
                    textModified: pathAttributes["text-mods"].map { $0 == "true" },
                    propertiesModified: pathAttributes["prop-mods"].map { $0 == "true" }
                ))
            }
            pathAttributes = nil
        case "property":
            if let propertyName {
                switch propertyName {
                case "svn:author": author = text
                case "svn:date":
                    date = fractionalDateFormatter.date(from: text) ?? dateFormatter.date(from: text)
                case "svn:log": message = text
                default:
                    revisionProperties.append(SVNRevisionProperty(name: propertyName, value: text))
                }
            }
            propertyName = nil
        case "logentry":
            let email = revisionProperties.first { property in
                let name = property.name.lowercased()
                return name == "email" || name == "author-email" || name == "author_email"
                    || name == "svn:author-email"
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
        default:
            break
        }
        text = ""
    }
}
