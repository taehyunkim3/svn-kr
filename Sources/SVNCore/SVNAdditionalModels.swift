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
