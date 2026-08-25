import Foundation
import SVNCore

enum TemporaryFileCleanupValidationFailure: Hashable {
    case unsafePath
    case missing
    case symbolicLink
    case notRegularFile
    case unreadable
    case invalidDSStoreSignature
    case invalidAppleDoubleSignature
    case officeLockFileTooLarge(maximumBytes: Int)

    var localizationKey: String {
        switch self {
        case .unsafePath: "ui.cleanup.reason.unsafe.path.5dce44a1"
        case .missing: "ui.cleanup.reason.file.missing.64ae4838"
        case .symbolicLink: "ui.cleanup.reason.symbolic.link.95821786"
        case .notRegularFile: "ui.cleanup.reason.not.regular.file.98aa0f60"
        case .unreadable: "ui.cleanup.reason.unreadable.85df36fb"
        case .invalidDSStoreSignature: "ui.cleanup.reason.invalid.ds.store.signature.2832697d"
        case .invalidAppleDoubleSignature: "ui.cleanup.reason.invalid.appledouble.signature.96cdf550"
        case .officeLockFileTooLarge: "ui.cleanup.reason.office.lock.too.large.38b4ef17"
        }
    }
}

struct TemporaryFileCleanupAssessment: Identifiable, Hashable {
    let path: String
    let failure: TemporaryFileCleanupValidationFailure?

    var id: String { path }
    var isEligible: Bool { failure == nil }
}

/// 임시파일의 표시와 커밋 포함 규칙을 한곳에서 결정합니다.
enum TemporaryFilePolicy {
    static let maximumOfficeLockFileSize = 4_096

    /// 이름상 임시파일인지 판정합니다. 버전관리 항목과 종류 미상 항목도 배지로
    /// 구분하되, 디렉터리는 파일 패턴과 이름이 같아도 임시파일로 보지 않습니다.
    static func isTemporaryFile(_ entry: SVNStatusEntry) -> Bool {
        guard entry.nodeKind != .directory else { return false }

        let name = (entry.path as NSString).lastPathComponent
        return name.hasPrefix("~$")
            || name == ".DS_Store"
            || name.hasPrefix("._")
            || name.hasSuffix(".swp")
            || name.hasSuffix(".swo")
            || name.hasSuffix("~")
            || (name.hasPrefix("#") && name.hasSuffix("#"))
            || name.hasPrefix(".#")
    }

    /// 목록과 커밋 대상에서 숨길 수 있는 항목은 기존 정책대로 확인된 미버전 파일로 제한합니다.
    static func isHideableTemporaryFile(_ entry: SVNStatusEntry) -> Bool {
        entry.item == .unversioned
            && entry.nodeKind == .file
            && isTemporaryFile(entry)
    }

    static func visibleEntries(
        _ entries: [SVNStatusEntry],
        hideTemporaryFiles: Bool
    ) -> [SVNStatusEntry] {
        guard hideTemporaryFiles else { return entries }
        return entries.filter { !isHideableTemporaryFile($0) }
    }

    static func commitEligibleEntries(
        _ entries: [SVNStatusEntry],
        hideTemporaryFiles: Bool
    ) -> [SVNStatusEntry] {
        visibleEntries(entries, hideTemporaryFiles: hideTemporaryFiles)
            .filter { $0.isSelectableForCommit || $0.canScheduleRepositoryDeletion }
    }

    static func automaticallySelectedEntries(_ entries: [SVNStatusEntry]) -> [SVNStatusEntry] {
        entries.filter {
            ($0.isSelectableForCommit || $0.canScheduleRepositoryDeletion)
                && !isHideableTemporaryFile($0)
        }
    }

    /// 저장소에서 자동 정리를 제안할 만큼 오탐 가능성이 낮은 이름만 허용합니다.
    static func isRepositoryCleanupCandidate(_ entry: SVNStatusEntry) -> Bool {
        isRepositoryCleanupCandidate(path: entry.path)
    }

    static func repositoryCleanupCandidates(
        in entries: [SVNStatusEntry]
    ) -> [SVNStatusEntry] {
        entries.filter { $0.item != .deleted && isRepositoryCleanupCandidate($0) }
    }

    static func validateRepositoryCleanupCandidates(
        paths: [String],
        in workingCopyURL: URL,
        fileManager: FileManager = .default
    ) -> [TemporaryFileCleanupAssessment] {
        paths.map { path in
            TemporaryFileCleanupAssessment(
                path: path,
                failure: repositoryCleanupValidationFailure(
                    for: path,
                    in: workingCopyURL,
                    fileManager: fileManager
                )
            )
        }
    }

    private static let officeExtensions: Set<String> = [
        "doc", "docx", "docm", "dot", "dotx",
        "xls", "xlsx", "xlsm", "xlsb",
        "ppt", "pptx", "ppsx", "pps",
    ]

    private static let nameOnlyCleanupCandidates: Set<String> = [
        "Icon\r",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".apdisk",
    ]

    private static func isRepositoryCleanupCandidate(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name == ".DS_Store" || name.hasPrefix("._") {
            return true
        }
        if nameOnlyCleanupCandidates.contains(name) {
            return true
        }
        guard name.hasPrefix("~$") else { return false }
        return officeExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func repositoryCleanupValidationFailure(
        for path: String,
        in workingCopyURL: URL,
        fileManager: FileManager
    ) -> TemporaryFileCleanupValidationFailure? {
        guard let fileURL = containedFileURL(for: path, in: workingCopyURL) else {
            return .unsafePath
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return .missing
        } catch {
            return .unreadable
        }

        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            return .symbolicLink
        }

        let name = (path as NSString).lastPathComponent
        if nameOnlyCleanupCandidates.contains(name) {
            return nil
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return .notRegularFile
        }

        if name.hasPrefix("~$") {
            let size = (attributes[.size] as? NSNumber)?.intValue ?? .max
            return size <= maximumOfficeLockFileSize
                ? nil
                : .officeLockFileTooLarge(maximumBytes: maximumOfficeLockFileSize)
        }

        let prefix: Data
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            prefix = try handle.read(upToCount: 8) ?? Data()
        } catch {
            return .unreadable
        }

        if name == ".DS_Store" {
            return prefix.starts(with: Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31]))
                ? nil
                : .invalidDSStoreSignature
        }
        return prefix.starts(with: Data([0x00, 0x05, 0x16, 0x07]))
            ? nil
            : .invalidAppleDoubleSignature
    }

    private static func containedFileURL(for path: String, in workingCopyURL: URL) -> URL? {
        // NSString은 "~$파일"도 홈 상대 절대 경로로 간주하므로 실제 루트 표식만 검사합니다.
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let components = (path as NSString).pathComponents
        guard !components.contains(".."), !components.contains(".") else { return nil }

        let root = workingCopyURL.standardizedFileURL
        // standardizedFileURL은 "~$파일"을 홈 경로로 오인해 확장할 수 있으므로,
        // 구성요소를 검증한 상대 경로는 그대로 붙입니다.
        let candidate = root.appendingPathComponent(path)
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        let resolvedRoot = root.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard resolvedCandidate.path.hasPrefix(resolvedRoot.path + "/") else { return nil }
        return candidate
    }
}
