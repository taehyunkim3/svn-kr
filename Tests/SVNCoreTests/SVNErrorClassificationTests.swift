import Foundation
import Testing
@testable import SVNCore

@Test func classifiesRequiredSVNErrorCodeFamilies() {
    #expect(SVNClient.isAuthenticationError("svn: E170001: Authentication required"))
    #expect(SVNClient.isAuthenticationError("svn: E215004: No more credentials"))
    #expect(SVNClient.isLockConflictError("svn: E195022: locked in another working copy"))
    #expect(SVNClient.isLockConflictError("svn: E160037: path is already locked"))
    #expect(SVNClient.isServerCertificateValidationError("svn: E175002: certificate failure"))
    #expect(SVNClient.isServerCertificateValidationError("svn: E230001: certificate expired"))
    #expect(SVNClient.isRepositoryConnectionError("svn: E170013: unable to connect"))
    #expect(SVNClient.isRepositoryConnectionError("svn: E180001: unable to open repository"))
    #expect(SVNClient.isWorkingCopyFormatTooOldError("svn: E155036: working copy is too old"))
    #expect(!SVNClient.isAuthenticationError("svn: E170013: unable to connect"))
}

@Test func classifiesCommandFailuresWithoutClassifyingUnrelatedErrors() {
    let commandError = SVNError.commandFailed(
        command: "svn commit",
        message: "svn: E195022: locked in another working copy"
    )
    #expect(SVNClient.isLockConflictError(commandError))
    #expect(!SVNClient.isLockConflictError(SVNError.invalidWorkingCopy))
}

@Test func exposesEveryCertificateFailureAcceptedBySVNHelp() {
    #expect(SVNServerCertificateFailure.allCases.map(\.rawValue) == [
        "unknown-ca", "cn-mismatch", "expired", "not-yet-valid", "other",
    ])
}

@Test func certificateFailureSelectionKeepsLegacyDefaultsAndAllowsExplicitValues() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("svn-certificate-options-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let executable = root.appendingPathComponent("svn")
    try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > arguments.txt\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let client = SVNClient(
        executablePath: executable.path,
        configDirectoryPath: root.appendingPathComponent("config").path
    )
    let legacyDestination = root.appendingPathComponent("legacy")
    _ = try await client.checkout(
        repositoryURL: "https://example.invalid/repository",
        destinationPath: legacyDestination.path,
        allowUntrustedServerCertificate: true
    )
    let legacyArguments = try String(
        contentsOf: legacyDestination.appendingPathComponent("arguments.txt"),
        encoding: .utf8
    )
    #expect(legacyArguments.contains("--trust-server-cert-failures=unknown-ca,cn-mismatch"))

    let explicitDestination = root.appendingPathComponent("explicit")
    _ = try await client.checkout(
        repositoryURL: "https://example.invalid/repository",
        destinationPath: explicitDestination.path,
        allowedServerCertificateFailures: [.expired, .notYetValid]
    )
    let explicitArguments = try String(
        contentsOf: explicitDestination.appendingPathComponent("arguments.txt"),
        encoding: .utf8
    )
    #expect(explicitArguments.contains("--trust-server-cert-failures=expired,not-yet-valid"))
    #expect(!explicitArguments.contains("unknown-ca"))

    let combinedDestination = root.appendingPathComponent("combined")
    _ = try await client.checkout(
        repositoryURL: "https://example.invalid/repository",
        destinationPath: combinedDestination.path,
        allowUntrustedServerCertificate: true,
        allowedServerCertificateFailures: [.expired]
    )
    let combinedArguments = try String(
        contentsOf: combinedDestination.appendingPathComponent("arguments.txt"),
        encoding: .utf8
    )
    #expect(combinedArguments.contains(
        "--trust-server-cert-failures=unknown-ca,cn-mismatch,expired"
    ))
}
