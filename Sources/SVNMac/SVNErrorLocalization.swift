import Foundation
import SVNCore

enum SVNErrorLocalization {
    static func message(for error: SVNError, language: AppLanguage) -> String {
        switch error {
        case let .commandFailed(command, message):
            return language.localized("ui.failed.cb475070", command, message)
        case let .workingCopyOutOfDate(details):
            return language.localized("ui.the.commit.is.based.on.an.older.working.copy.sta.834c44c4", details)
        case .invalidWorkingCopy:
            return language.localized("ui.the.selected.folder.is.not.an.svn.local.working..c602474e")
        case .malformedResponse:
            return language.localized("ui.the.svn.response.could.not.be.read.6a3d5aa8")
        case let .pathNormalizationCollision(paths):
            return language.localized("error.path.normalization.collision", paths.joined(separator: ", "))
        case let .pathAliasRepairFailed(paths):
            return language.localized("error.path.alias.repair", paths.joined(separator: ", "))
        case let .fileReplacementRecoveryFailed(paths, backupPaths):
            return language.localized(
                "error.file.replacement.recovery",
                paths.joined(separator: ", "),
                backupPaths.joined(separator: ", ")
            )
        case let .unsupportedTargetPath(paths):
            return language.localized("error.unsupported.target.path", paths.joined(separator: ", "))
        case let .unresolvedMissingPaths(paths):
            return language.localized("error.unresolved.missing.paths", paths.joined(separator: ", "))
        case let .deletionValidationFailed(paths):
            return language.localized("error.deletion.validation", paths.joined(separator: ", "))
        case let .commitSucceededWithValidationWarning(_, details):
            return language.localized("ui.the.commit.completed.but.working.copy.validation.e58fd53c", details)
        case let .recoveryBlocked(paths):
            return language.localized("error.recovery.blocked", paths.joined(separator: ", "))
        case .recoveryDestinationNotEmpty:
            return language.localized("ui.the.recovery.destination.folder.must.be.empty.2f9bc173")
        case let .recoveryValidationFailed(paths):
            return language.localized("error.recovery.validation", paths.joined(separator: ", "))
        case .svnExecutableNotFound:
            return language.localized("ui.the.bundled.svn.executable.could.not.be.found.re.8656fcae")
        }
    }

    static func message(for error: ConflictFileError, language: AppLanguage) -> String {
        switch error {
        case let .unsupportedType(type):
            return language.localized("ui.unsupported.conflict.type.1a0e94e8", type)
        case .missingMine:
            return language.localized("ui.your.file.version.could.not.be.found.576883d5")
        case .missingServer:
            return language.localized("ui.the.server.file.version.could.not.be.found.3483616c")
        case .missingWorkingFile:
            return language.localized("ui.the.current.working.file.could.not.be.found.60c92e05")
        case .sourceOutsideWorkingCopy:
            return language.localized("ui.a.conflict.file.path.points.outside.the.working..137a7ed6")
        case .backupRootInsideWorkingCopy:
            return language.localized("ui.conflict.backups.must.be.stored.outside.the.work.b1ccd27c")
        case .unsafeMineSource:
            return language.localized("ui.your.file.version.must.be.a.regular.file.not.a.s.0ea5ff6f")
        case .unsafeServerSource:
            return language.localized("ui.the.server.file.version.must.be.a.regular.file.n.7eb568b2")
        case .unsafeWorkingFile:
            return language.localized("ui.the.current.working.file.must.be.a.regular.file..1af7fbcd")
        case .workingRecoveryVerificationFailed:
            return language.localized("ui.the.recovery.backup.of.the.current.working.file..048b3539")
        case .workingRestoreVerificationFailed:
            return language.localized("ui.the.selected.version.of.your.file.could.not.be.r.70a89d83")
        case .conflictResolutionVerificationFailed:
            return language.localized("ui.the.conflict.remains.after.the.svn.command.revie.2162b675")
        case let .cleanupFailed(message):
            return language.localized("ui.failed.to.remove.an.incomplete.conflict.backup.65753038", message)
        }
    }
}
