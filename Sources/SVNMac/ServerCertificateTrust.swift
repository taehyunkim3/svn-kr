import Foundation
import SVNCore

struct ServerCertificateTrust: Equatable {
    let failures: Set<SVNServerCertificateFailure>
    let diagnosticDetails: String

    var failure: SVNServerCertificateFailure {
        SVNServerCertificateFailure.allCases.first(where: failures.contains) ?? .other
    }

    var canAllow: Bool {
        !failures.isEmpty && !failures.contains(.other)
    }
}
