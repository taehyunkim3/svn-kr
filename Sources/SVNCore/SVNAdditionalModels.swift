import Foundation

public enum SVNServerCertificateFailure: String, CaseIterable, Hashable, Sendable {
    case unknownCertificateAuthority = "unknown-ca"
    case commonNameMismatch = "cn-mismatch"
    case expired
    case notYetValid = "not-yet-valid"
    case other
}

public struct SVNProperty: Identifiable, Hashable, Sendable {
    public let name: String
    public let value: Data

    public var id: String { name }

    public init(name: String, value: Data) {
        self.name = name
        self.value = value
    }
}

public enum SVNRepositoryEntryKind: Hashable, Sendable {
    case file
    case directory
}

public struct SVNRepositoryEntry: Identifiable, Hashable, Sendable {
    public let name: String
    public let kind: SVNRepositoryEntryKind
    public let size: Int64?
    public let lastChangedRevision: String
    public let lastChangedAuthor: String?
    public let lastChangedDate: Date?

    public var id: String { name }

    public init(
        name: String,
        kind: SVNRepositoryEntryKind,
        size: Int64?,
        lastChangedRevision: String,
        lastChangedAuthor: String?,
        lastChangedDate: Date?
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.lastChangedRevision = lastChangedRevision
        self.lastChangedAuthor = lastChangedAuthor
        self.lastChangedDate = lastChangedDate
    }
}
