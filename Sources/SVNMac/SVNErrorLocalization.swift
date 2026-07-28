import Foundation
import SVNCore

enum SVNErrorLocalization {
    static func message(for error: SVNError, language: AppLanguage) -> String {
        switch error {
        case let .commandFailed(command, message):
            return language.text("\(command) 실패: \(message)", "\(command) failed: \(message)")
        case let .workingCopyOutOfDate(details):
            return language.text(
                "서버에서 먼저 변경된 항목이 있어 커밋할 수 없습니다. 작업 폴더를 업데이트하고 충돌이 있으면 해결한 뒤 다시 커밋하세요.\n\n\(details)",
                "The commit is based on an older working-copy state. Run Update, resolve any conflicts, and then commit again.\n\n\(details)"
            )
        case .invalidWorkingCopy:
            return language.text("선택한 폴더는 SVN 로컬 작업 폴더가 아닙니다.", "The selected folder is not an SVN local working folder.")
        case .malformedResponse:
            return language.text("SVN 응답을 읽지 못했습니다.", "The SVN response could not be read.")
        case let .pathNormalizationCollision(paths):
            return language.text(
                "한글 경로 충돌이 있어 작업을 중단했습니다: \(paths.joined(separator: ", "))",
                "Korean path normalization conflicts must be recovered before continuing: \(paths.joined(separator: ", "))"
            )
        case let .pathAliasRepairFailed(paths):
            return language.text(
                "한글 경로 별칭 정리를 검증하지 못했습니다: \(paths.joined(separator: ", "))",
                "Korean path alias repair could not be validated: \(paths.joined(separator: ", "))"
            )
        case let .fileReplacementRecoveryFailed(paths, backupPaths):
            return language.text(
                "대치 파일을 원래 위치로 복원하지 못했습니다: \(paths.joined(separator: ", ")). 백업 파일: \(backupPaths.joined(separator: ", "))",
                "Replacement files could not be restored to their original paths: \(paths.joined(separator: ", ")). Backups: \(backupPaths.joined(separator: ", "))"
            )
        case let .unsupportedTargetPath(paths):
            return language.text(
                "SVN 명령에 안전하게 전달할 수 없는 줄바꿈 경로가 있습니다: \(paths.joined(separator: ", "))",
                "Paths containing line breaks cannot be passed safely to SVN: \(paths.joined(separator: ", "))"
            )
        case let .unresolvedMissingPaths(paths):
            return language.text(
                "로컬 누락 항목의 처리 방법을 먼저 선택해야 합니다: \(paths.joined(separator: ", "))",
                "Choose how to handle locally missing items first: \(paths.joined(separator: ", "))"
            )
        case let .deletionValidationFailed(paths):
            return language.text(
                "저장소 삭제 예정 상태로 전환되지 않은 항목이 있습니다: \(paths.joined(separator: ", "))",
                "These items did not enter the pending-deletion state: \(paths.joined(separator: ", "))"
            )
        case let .commitSucceededWithValidationWarning(_, details):
            return language.text(
                "커밋은 완료되었지만 작업 폴더 검증에 실패했습니다. 다시 커밋하지 말고 새로고침 결과를 확인하세요: \(details)",
                "The commit completed, but working-copy validation failed. Do not retry the commit; review the refreshed status: \(details)"
            )
        case let .recoveryBlocked(paths):
            return language.text(
                "자동 복구할 수 없는 변경이 있습니다: \(paths.joined(separator: ", "))",
                "Some changes cannot be recovered automatically: \(paths.joined(separator: ", "))"
            )
        case .recoveryDestinationNotEmpty:
            return language.text("복구 대상 폴더는 비어 있어야 합니다.", "The recovery destination folder must be empty.")
        case let .recoveryValidationFailed(paths):
            return language.text(
                "새 작업 폴더 검증에 실패했습니다: \(paths.joined(separator: ", "))",
                "The recovered working copy did not pass validation: \(paths.joined(separator: ", "))"
            )
        case .svnExecutableNotFound:
            return language.text(
                "앱에 포함된 SVN 실행 파일을 찾지 못했습니다. 앱을 다시 설치해 주세요.",
                "The bundled SVN executable could not be found. Reinstall the app."
            )
        }
    }

    static func message(for error: ConflictFileError, language: AppLanguage) -> String {
        switch error {
        case let .unsupportedType(type):
            return language.text("지원하지 않는 충돌 유형입니다: \(type)", "Unsupported conflict type: \(type)")
        case .missingMine:
            return language.text("내 파일 버전을 찾을 수 없습니다.", "Your file version could not be found.")
        case .missingServer:
            return language.text("서버 파일 버전을 찾을 수 없습니다.", "The server file version could not be found.")
        case .missingWorkingFile:
            return language.text("현재 작업 파일을 찾을 수 없습니다.", "The current working file could not be found.")
        case .sourceOutsideWorkingCopy:
            return language.text("충돌 파일 경로가 작업 사본 밖을 가리킵니다.", "A conflict file path points outside the working copy.")
        case .backupRootInsideWorkingCopy:
            return language.text("충돌 백업 위치는 작업 사본 밖에 있어야 합니다.", "Conflict backups must be stored outside the working copy.")
        case .unsafeMineSource:
            return language.text("내 파일 버전은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다.", "Your file version must be a regular file, not a symbolic link.")
        case .unsafeServerSource:
            return language.text("서버 파일 버전은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다.", "The server file version must be a regular file, not a symbolic link.")
        case .unsafeWorkingFile:
            return language.text("현재 작업 파일은 일반 파일이어야 하며 심볼릭 링크일 수 없습니다.", "The current working file must be a regular file, not a symbolic link.")
        case .workingRecoveryVerificationFailed:
            return language.text("현재 작업 파일의 복구 백업을 검증하지 못했습니다.", "The recovery backup of the current working file could not be verified.")
        case .workingRestoreVerificationFailed:
            return language.text("선택한 내 파일 버전을 작업 파일에 복원하지 못했습니다.", "The selected version of your file could not be restored to the working file.")
        case .conflictResolutionVerificationFailed:
            return language.text(
                "SVN 명령 이후에도 충돌 상태가 남아 있습니다. 백업을 확인한 뒤 다시 시도하세요.",
                "The conflict remains after the SVN command. Review the backups and try again."
            )
        case let .cleanupFailed(message):
            return language.text(
                "불완전한 충돌 백업 정리에 실패했습니다: \(message)",
                "Failed to remove an incomplete conflict backup: \(message)"
            )
        }
    }
}
