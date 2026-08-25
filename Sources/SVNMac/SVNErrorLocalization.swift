import Foundation
import SVNCore

enum SVNErrorLocalization {
    private static let serverCertificateFailureReasons: [
        (String, SVNServerCertificateFailure)
    ] = [
        ("certificate is not yet valid", .notYetValid),
        ("certificate has expired", .expired),
        ("certificate issued for a different hostname", .commonNameMismatch),
        ("issuer is not trusted", .unknownCertificateAuthority),
    ]

    private enum FailureCode: Equatable {
        case needsCleanup
        case remainsInConflict(path: String)
        case notLockedInWorkingCopy
    }

    static func message(for error: SVNError, language: AppLanguage) -> String {
        switch error {
        case let .commandFailed(command, message):
            if let failures = serverCertificateFailures(for: error) {
                let guidance = SVNServerCertificateFailure.allCases
                    .filter(failures.contains)
                    .map { serverCertificateGuidance(for: $0, language: language) }
                    .joined(separator: "\n\n")
                return "\(guidance)\n\n\(message)"
            }
            switch failureCode(in: message) {
            case .needsCleanup:
                return language.localized(
                    .ui.working.copyOperationInterruptedRunCleanup,
                    message
                )
            case let .remainsInConflict(path):
                return language.localized(
                    .ui.file.remainsInConflictResolveBeforeRetry,
                    path,
                    message
                )
            case .notLockedInWorkingCopy:
                return language.localized(
                    .ui.lock.belongsToAnotherWorkingCopyForceUnlock,
                    message
                )
            case nil:
                return language.localized(.ui.failed.label, command, message)
            }
        case let .workingCopyOutOfDate(details):
            return language.localized(.ui.the.commitIsBasedOnAnOlderWorkingCopySta, details)
        case .invalidWorkingCopy:
            return language.localized(.ui.the.selectedFolderIsNotAnSvnLocalWorking)
        case .malformedResponse:
            return language.localized(.ui.the.svnResponseCouldNotBeRead)
        case let .pathNormalizationCollision(paths):
            return language.localized(.error.pathNormalizationCollision, paths.joined(separator: ", "))
        case let .pathAliasRepairFailed(paths):
            return language.localized(.error.pathAliasRepair, paths.joined(separator: ", "))
        case let .fileReplacementRecoveryFailed(paths, backupPaths):
            return language.localized(
                .error.fileReplacementRecovery,
                paths.joined(separator: ", "),
                backupPaths.joined(separator: ", ")
            )
        case let .unsupportedTargetPath(paths):
            return language.localized(.error.unsupportedTargetPath, paths.joined(separator: ", "))
        case let .unresolvedMissingPaths(paths):
            return language.localized(.error.unresolvedMissingPaths, paths.joined(separator: ", "))
        case let .deletionValidationFailed(paths):
            return language.localized(.error.deletionValidation, paths.joined(separator: ", "))
        case let .commitSucceededWithValidationWarning(_, details):
            return language.localized(.ui.the.commitCompletedButWorkingCopyValidation, details)
        case let .recoveryBlocked(paths):
            return language.localized(.error.recoveryBlocked, paths.joined(separator: ", "))
        case .recoveryDestinationNotEmpty:
            return language.localized(.ui.the.recoveryDestinationFolderMustBeEmpty)
        case let .recoveryValidationFailed(paths):
            return language.localized(.error.recoveryValidation, paths.joined(separator: ", "))
        case .svnExecutableNotFound:
            return language.localized(.ui.the.bundledSvnExecutableCouldNotBeFoundRe)
        }
    }

    static func diagnosticDetails(for error: Error) -> String {
        guard let svnError = error as? SVNError else { return error.localizedDescription }
        if case let .commandFailed(command, message) = svnError {
            return "\(command)\n\(message)"
        }
        return String(describing: svnError)
    }

    static func serverCertificateFailures(
        for error: Error
    ) -> Set<SVNServerCertificateFailure>? {
        guard SVNClient.isServerCertificateValidationError(error) else { return nil }
        let message = diagnosticDetails(for: error).lowercased()
        let failures = Set(serverCertificateFailureReasons.compactMap { reason, failure in
            message.contains(reason) ? failure : nil
        })
        return failures.isEmpty ? [.other] : failures
    }

    static func serverCertificateFailure(
        for error: Error
    ) -> SVNServerCertificateFailure? {
        guard let failures = serverCertificateFailures(for: error) else { return nil }
        guard failures.count == 1 else { return .other }
        return failures.first
    }

    static func serverCertificateGuidance(
        for failure: SVNServerCertificateFailure,
        language: AppLanguage
    ) -> String {
        switch failure {
        case .unknownCertificateAuthority:
            language.localized(.ui.certificate.unknownCaGuidance)
        case .commonNameMismatch:
            language.localized(.ui.certificate.nameMismatchGuidance)
        case .expired:
            language.localized(.ui.certificate.expiredGuidance)
        case .notYetValid:
            language.localized(.ui.certificate.notYetValidGuidance)
        case .other:
            language.localized(.ui.certificate.unclassifiedGuidance)
        }
    }

    static func suggestsForceUnlock(_ error: Error) -> Bool {
        guard case let SVNError.commandFailed(_, message) = error else { return false }
        return failureCode(in: message) == .notLockedInWorkingCopy
    }

    private static func failureCode(in message: String) -> FailureCode? {
        if SVNClient.needsCleanup(message) { return .needsCleanup }
        if message.contains("E155015") {
            return .remainsInConflict(path: conflictPath(in: message) ?? message)
        }
        if message.contains("E195013") { return .notLockedInWorkingCopy }
        return nil
    }

    private static func conflictPath(in message: String) -> String? {
        let pattern = #"['\"]([^'\"]+)['\"]\s+remains in conflict"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: message,
                  range: NSRange(message.startIndex..., in: message)
              ),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return String(message[range])
    }

    static func message(for error: ConflictFileError, language: AppLanguage) -> String {
        switch error {
        case let .unsupportedType(type):
            return [
                language.localized(.ui.unsupported.conflictType, type),
                [
                    language.localized(.ui.revert.localChangesAction),
                    language.localized(.ui.run.update),
                ].joined(separator: " → "),
            ].joined(separator: "\n")
        case .missingMine:
            return language.localized(.ui.your.fileVersionCouldNotBeFound)
        case .missingServer:
            return language.localized(.ui.the.serverFileVersionCouldNotBeFound)
        case .missingWorkingFile:
            return language.localized(.ui.the.currentWorkingFileCouldNotBeFound)
        case .sourceOutsideWorkingCopy:
            return language.localized(.ui.a.conflictFilePathPointsOutsideTheWorking)
        case .backupRootInsideWorkingCopy:
            return language.localized(.ui.conflict.backupsMustBeStoredOutsideTheWork)
        case .unsafeMineSource:
            return language.localized(.ui.your.fileVersionMustBeARegularFileNotAS)
        case .unsafeServerSource:
            return language.localized(.ui.the.serverFileVersionMustBeARegularFileN)
        case .unsafeWorkingFile:
            return language.localized(.ui.the.currentWorkingFileMustBeARegularFile)
        case .workingRecoveryVerificationFailed:
            return language.localized(.ui.the.recoveryBackupOfTheCurrentWorkingFile)
        case .workingRestoreVerificationFailed:
            return language.localized(.ui.the.selectedVersionOfYourFileCouldNotBeR)
        case .conflictResolutionVerificationFailed:
            return language.localized(.ui.the.conflictRemainsAfterTheSvnCommandRevie)
        case let .cleanupFailed(message):
            return language.localized(.ui.failed.toRemoveAnIncompleteConflictBackup, message)
        }
    }
}
