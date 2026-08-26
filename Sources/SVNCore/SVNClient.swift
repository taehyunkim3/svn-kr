import Foundation
import Darwin

public typealias SVNOutputHandler = @Sendable (String) -> Void

/// 파일 단위 SVN 명령을 작업 복사본 루트에서 실행하기 위해 필요한 경로입니다.
/// `workingCopyRootPath`는 로컬 실행 위치이고, `svnPathRelativeToWorkingCopyRoot`는
/// SVN이 실제로 관리하는 원문 UTF-8 경로이므로 서로 대신 사용할 수 없습니다.
private struct SVNWorkingCopyCommandPath {
    let workingCopyRootPath: String
    let svnProjectPathPrefixRelativeToWorkingCopyRoot: String
    let svnPathRelativeToWorkingCopyRoot: String
}

/// SVN CLI 호출을 직렬화하는 코어 서비스입니다.
///
/// actor로 선언해 동일 클라이언트에서 update와 commit 같은 명령이 동시에
/// 작업 복사본을 변경하지 않도록 보장합니다. 실제 CLI 실행은 `run` 한곳을
/// 통과하므로 인증 인자와 출력 수집 방식도 모든 명령에서 동일합니다.
public actor SVNClient {
    private struct ProjectPathPrefixCacheEntry {
        let prefix: String
        let workingCopyMetadataModificationDate: Date?
    }

    private let executablePath: String?
    private let configDirectoryPath: String?
    private var svnProjectPathPrefixByLocalProjectPath: [
        SVNPathIdentity: ProjectPathPrefixCacheEntry
    ] = [:]

    public init(executablePath: String? = nil, configDirectoryPath: String? = nil) {
        self.executablePath = executablePath
        self.configDirectoryPath = configDirectoryPath
    }

    // MARK: - 사용자가 실행하는 SVN 기능

    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        try await checkout(
            repositoryURL: repositoryURL,
            destinationPath: destinationPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: nil
        )
    }

    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [],
        progress: SVNOutputHandler?
    ) async throws -> String {
        let repositoryURL = URL(string: repositoryURL)?.absoluteString ?? repositoryURL
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return try await checkedRunWithSVNPathArguments(
            ["checkout"],
            svnPathArguments: [repositoryURL, "."],
            escapePegSyntax: [true, false],
            at: destination.path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: progress
        ).output
    }

    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        credentials: SVNCredentials? = nil,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    ) async throws -> String {
        try await checkout(
            repositoryURL: repositoryURL,
            destinationPath: destinationPath,
            credentials: credentials,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: nil
        )
    }

    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        credentials: SVNCredentials? = nil,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>,
        progress: SVNOutputHandler?
    ) async throws -> String {
        let repositoryURL = URL(string: repositoryURL)?.absoluteString ?? repositoryURL
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return try await checkedRunWithSVNPathArguments(
            ["checkout"],
            svnPathArguments: [repositoryURL, "."],
            escapePegSyntax: [true, false],
            at: destination.path,
            credentials: credentials,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: progress
        ).output
    }

    /// 지정한 리비전으로 체크아웃합니다. 복구처럼 원본 작업 복사본의 BASE를 그대로
    /// 재현해야 하는 흐름은 HEAD로 체크아웃하면 그 사이 다른 사람이 올린 커밋을
    /// out-of-date 검사 없이 덮어쓰게 되므로 이 오버로드를 사용합니다.
    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        revision: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [],
        progress: SVNOutputHandler? = nil
    ) async throws -> String {
        guard let revisionNumber = Int(revision), revisionNumber >= 0 else {
            throw SVNClientArgumentError.unsupportedRevision(revision)
        }
        let repositoryURL = URL(string: repositoryURL)?.absoluteString ?? repositoryURL
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return try await checkedRunWithSVNPathArguments(
            ["checkout", "--revision", String(revisionNumber)],
            svnPathArguments: [repositoryURL, "."],
            escapePegSyntax: [true, false],
            at: destination.path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: progress
        ).output
    }

    public func validateWorkingCopy(at path: String, credentials: SVNCredentials? = nil) async throws {
        let result = try await run(["info", "--show-item", "wc-root"], at: path, credentials: credentials)
        guard result.exitCode == 0 else { throw SVNError.invalidWorkingCopy }
    }

    public func workingCopyRepositoryURL(at path: String, credentials: SVNCredentials? = nil) async throws -> String {
        try await checkedRun(["info", "--show-item", "url"], at: path, credentials: credentials)
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func fileContents(
        at path: String,
        relativePath: String,
        revision: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> Data {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-cat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let outputURL = temporaryDirectory.appendingPathComponent("contents", isDirectory: false)
        _ = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["cat", "--revision", revision],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            outputDestinationURL: outputURL
        )
        return try Data(contentsOf: outputURL)
    }

    public func export(
        at path: String,
        relativePath: String,
        revision: String,
        destinationPath: String,
        force: Bool = false,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        let commandPath = try await resolveWorkingCopyCommandPath(
            localProjectPath: path,
            projectRelativePath: relativePath,
            credentials: credentials
        )
        var arguments = ["export", "--revision", revision]
        if force { arguments.append("--force") }
        return try await checkedRunWithTwoSVNPathArguments(
            arguments,
            firstSVNPathArgument: commandPath.svnPathRelativeToWorkingCopyRoot,
            secondSVNPathArgument: URL(fileURLWithPath: destinationPath).standardizedFileURL.path,
            at: commandPath.workingCopyRootPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ).output
    }

    public func move(
        at path: String,
        sourceRelativePath: String,
        destinationRelativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try await runWorkingCopyCopyOrMove(
            "move",
            at: path,
            sourceRelativePath: sourceRelativePath,
            destinationRelativePath: destinationRelativePath,
            credentials: credentials
        )
    }

    public func copy(
        at path: String,
        sourceRelativePath: String,
        destinationRelativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try await runWorkingCopyCopyOrMove(
            "copy",
            at: path,
            sourceRelativePath: sourceRelativePath,
            destinationRelativePath: destinationRelativePath,
            credentials: credentials
        )
    }

    public func copy(
        repositoryURL: String,
        revision: String? = nil,
        to destinationRelativePath: String,
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        let destination = try await resolveWorkingCopyCommandPath(
            localProjectPath: path,
            projectRelativePath: destinationRelativePath,
            credentials: credentials
        )
        var arguments = ["copy"]
        if let revision, !revision.isEmpty { arguments += ["--revision", revision] }
        let sourceURL: String
        let escapeSourcePegSyntax: Bool
        if let revision, !revision.isEmpty {
            sourceURL = repositoryURL + "@" + revision
            escapeSourcePegSyntax = false
        } else {
            sourceURL = repositoryURL
            escapeSourcePegSyntax = true
        }
        return try await checkedRunWithTwoSVNPathArguments(
            arguments,
            firstSVNPathArgument: sourceURL,
            secondSVNPathArgument: Self.normalizedNewDestinationPath(
                destination.svnPathRelativeToWorkingCopyRoot
            ),
            escapeFirstPegSyntax: escapeSourcePegSyntax,
            at: destination.workingCopyRootPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ).output
    }

    public func relocate(
        at path: String,
        fromRepositoryURL: String,
        toRepositoryURL: String,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        let projectCommandPath = try await resolveWorkingCopyCommandPath(
            localProjectPath: path,
            projectRelativePath: ".",
            credentials: credentials
        )
        let workingCopyRootURL = try await workingCopyRepositoryURL(
            at: projectCommandPath.workingCopyRootPath,
            credentials: nil
        )
        let currentProjectURL = try await workingCopyRepositoryURL(at: path, credentials: nil)
        let projectURLSuffix = currentProjectURL.hasPrefix(workingCopyRootURL)
            ? String(currentProjectURL.dropFirst(workingCopyRootURL.count))
            : ""
        let oldURL = fromRepositoryURL == currentProjectURL
            ? workingCopyRootURL
            : fromRepositoryURL
        let newURL = !projectURLSuffix.isEmpty && toRepositoryURL.hasSuffix(projectURLSuffix)
            ? String(toRepositoryURL.dropLast(projectURLSuffix.count))
            : toRepositoryURL
        return try await checkedRunWithSVNPathArguments(
            ["relocate"],
            svnPathArguments: [oldURL, newURL, "."],
            escapePegSyntax: [false, false, false],
            at: projectCommandPath.workingCopyRootPath,
            credentials: credentials
        ).output
    }

    public func setProperty(
        named name: String,
        value: Data,
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try Self.validatePropertyName(name)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-property-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let valueURL = temporaryDirectory.appendingPathComponent("value", isDirectory: false)
        try value.write(to: valueURL, options: .atomic)
        return try await checkedRunWithSingleWorkingCopyPathArgument(
            ["propset", name, "--file", valueURL.path],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials
        ).output
    }

    public func propertyValue(
        named name: String,
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws -> Data {
        try Self.validatePropertyName(name)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-propget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let outputURL = temporaryDirectory.appendingPathComponent("value", isDirectory: false)
        _ = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["propget", name, "--no-newline"],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials,
            outputDestinationURL: outputURL
        )
        return try Data(contentsOf: outputURL)
    }

    public func deleteProperty(
        named name: String,
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try Self.validatePropertyName(name)
        return try await checkedRunWithSingleWorkingCopyPathArgument(
            ["propdel", name],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials
        ).output
    }

    public func properties(
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws -> [SVNProperty] {
        let result = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["proplist", "--xml", "--verbose"],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials
        )
        return try SVNXMLParser.properties(from: Data(result.output.utf8))
    }

    private func runWorkingCopyCopyOrMove(
        _ command: String,
        at path: String,
        sourceRelativePath: String,
        destinationRelativePath: String,
        credentials: SVNCredentials?
    ) async throws -> String {
        let source = try await resolveWorkingCopyCommandPath(
            localProjectPath: path,
            projectRelativePath: sourceRelativePath,
            credentials: credentials
        )
        let destination = try await resolveWorkingCopyCommandPath(
            localProjectPath: path,
            projectRelativePath: destinationRelativePath,
            credentials: credentials
        )
        return try await checkedRunWithTwoSVNPathArguments(
            [command],
            firstSVNPathArgument: source.svnPathRelativeToWorkingCopyRoot,
            secondSVNPathArgument: Self.normalizedNewDestinationPath(
                destination.svnPathRelativeToWorkingCopyRoot
            ),
            escapeSecondPegSyntax: command != "move",
            at: source.workingCopyRootPath,
            credentials: credentials
        ).output
    }

    public func repositoryPathsNeedingNormalization(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNRepositoryPathNormalizationTarget] {
        let repositoryURL = try await workingCopyRepositoryURL(at: path, credentials: credentials)
        let result = try await checkedRun(
            ["list", "--recursive", "--xml", "--", Self.svnPathEscapingPegSyntax(repositoryURL)],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        let entries = try SVNXMLParser.repositoryListEntries(from: Data(result.output.utf8))
        return SVNRepositoryPathNormalization.targets(from: entries)
    }

    public func repositoryEntries(
        at repositoryURL: String,
        revision: String? = nil,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNRepositoryEntry] {
        var arguments = ["list", "--xml"]
        if let revision, !revision.isEmpty {
            arguments += ["--revision", revision]
        }
        let repositoryURLArgument: String
        let escapePegSyntax: Bool
        if let revision, !revision.isEmpty {
            repositoryURLArgument = repositoryURL + "@" + revision
            escapePegSyntax = false
        } else {
            repositoryURLArgument = repositoryURL
            escapePegSyntax = true
        }
        let result = try await checkedRunWithSingleSVNPathArgument(
            arguments,
            svnPathArgument: repositoryURLArgument,
            escapePegSyntax: escapePegSyntax,
            at: FileManager.default.temporaryDirectory.path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.repositoryEntries(from: Data(result.output.utf8))
    }

    public func normalizeRepositoryPaths(
        _ targets: [SVNRepositoryPathNormalizationTarget],
        at path: String,
        message: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> SVNRepositoryPathNormalizationResult {
        let targets = SVNRepositoryPathNormalization.minimalTargets(targets)
        guard !targets.isEmpty else {
            return SVNRepositoryPathNormalizationResult(
                renamedTargets: [],
                skippedTargets: [],
                committedRevisions: []
            )
        }
        let messageFile = try Self.makeSVNLogMessageFile(message)
        defer { try? FileManager.default.removeItem(at: messageFile.directory) }

        let invalidTargets = targets.filter { target in
            !SVNRepositoryPathNormalization.isValidTarget(target)
        }
        guard invalidTargets.isEmpty else {
            throw SVNRepositoryPathNormalizationError.invalidTargets(
                paths: invalidTargets.map(\.repositoryPath)
            )
        }

        let snapshot = try await workingCopySnapshot(at: path, credentials: credentials)
        // 스냅샷의 표시 목록은 정상·무시·external 항목을 이미 제외합니다. 남는 것은
        // 내용 변경, 속성 전용 변경, switched, 미버전 문서처럼 서버 경로가 움직이면
        // 옛 이름 아래에 남거나 트리 충돌이 되는 항목이므로 전부 차단 대상입니다.
        let blockingLocalPaths = snapshot.statuses.compactMap { entry -> String? in
            targets.contains(where: {
                SVNRepositoryPathNormalization.isAtOrBelowCanonicalPath(
                    entry.path,
                    root: $0.repositoryPath
                )
            }) ? entry.path : nil
        }
        guard blockingLocalPaths.isEmpty else {
            throw SVNRepositoryPathNormalizationError.blockedByLocalChanges(
                paths: blockingLocalPaths
            )
        }

        let locks = try await repositoryLocks(
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        let blockingLockPaths = locks.compactMap { lock in
            targets.contains(where: {
                SVNRepositoryPathNormalization.isAtOrBelowCanonicalPath(
                    lock.path,
                    root: $0.repositoryPath
                )
            }) ? lock.path : nil
        }
        guard blockingLockPaths.isEmpty else {
            throw SVNRepositoryPathNormalizationError.blockedByLocks(paths: blockingLockPaths)
        }

        let repositoryURL = try await workingCopyRepositoryURL(at: path, credentials: credentials)
        let listResult = try await checkedRun(
            ["list", "--recursive", "--xml", "--", Self.svnPathEscapingPegSyntax(repositoryURL)],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        let repositoryEntries = try SVNXMLParser.repositoryListEntries(
            from: Data(listResult.output.utf8)
        )
        let repositoryPathBytes = Set(repositoryEntries.map { Data($0.path.utf8) })
        let skippedTargets = targets.filter {
            repositoryPathBytes.contains(Data($0.normalizedPath.utf8))
        }
        let skippedPathBytes = Set(skippedTargets.map { Data($0.repositoryPath.utf8) })

        struct PendingTarget {
            let original: SVNRepositoryPathNormalizationTarget
            var repositoryPath: String
            var normalizedPath: String
        }
        var pending = targets.compactMap { target -> PendingTarget? in
            guard !skippedPathBytes.contains(Data(target.repositoryPath.utf8)) else { return nil }
            return PendingTarget(
                original: target,
                repositoryPath: target.repositoryPath,
                normalizedPath: target.normalizedPath
            )
        }
        var renamedTargets: [SVNRepositoryPathNormalizationTarget] = []
        var committedRevisions: [String] = []

        while !pending.isEmpty {
            let current = pending.removeFirst()
            let sourceURL = SVNRepositoryPathNormalization.repositoryURL(
                repositoryURL,
                appending: current.repositoryPath
            )
            let destinationURL = SVNRepositoryPathNormalization.repositoryURL(
                repositoryURL,
                appending: current.normalizedPath
            )
            let result: SVNCommandResult
            do {
                result = try await run(
                    ["move", "--file", messageFile.path, "--force-log"],
                    svnPathArguments: [
                        Self.svnPathEscapingPegSyntax(sourceURL),
                        destinationURL,
                    ],
                    at: path,
                    credentials: credentials,
                    allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                    allowedServerCertificateFailures: allowedServerCertificateFailures
                )
            } catch {
                throw SVNRepositoryPathNormalizationError.failed(
                    result: SVNRepositoryPathNormalizationResult(
                        renamedTargets: renamedTargets,
                        skippedTargets: skippedTargets,
                        committedRevisions: committedRevisions
                    ),
                    failedTarget: current.original,
                    details: String(describing: error)
                )
            }
            guard result.exitCode == 0,
                  let revision = SVNRepositoryPathNormalization.committedRevision(
                      from: result.output
                  ) else {
                let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SVNRepositoryPathNormalizationError.failed(
                    result: SVNRepositoryPathNormalizationResult(
                        renamedTargets: renamedTargets,
                        skippedTargets: skippedTargets,
                        committedRevisions: committedRevisions
                    ),
                    failedTarget: current.original,
                    details: detail.isEmpty ? result.output : detail
                )
            }

            renamedTargets.append(current.original)
            committedRevisions.append(revision)
            for index in pending.indices {
                pending[index].repositoryPath = SVNRepositoryPathNormalization.replacingRawPrefix(
                    in: pending[index].repositoryPath,
                    sourcePrefix: current.repositoryPath,
                    destinationPrefix: current.normalizedPath
                )
                pending[index].normalizedPath = SVNRepositoryPathNormalization.replacingRawPrefix(
                    in: pending[index].normalizedPath,
                    sourcePrefix: current.repositoryPath,
                    destinationPrefix: current.normalizedPath
                )
            }
        }

        return SVNRepositoryPathNormalizationResult(
            renamedTargets: renamedTargets,
            skippedTargets: skippedTargets,
            committedRevisions: committedRevisions
        )
    }

    /// 주어진 자격 증명으로 저장소에 실제로 접근할 수 있는지 확인합니다.
    ///
    /// 작업 복사본 대상 `info`는 로컬 메타데이터만 읽어 인증을 거치지 않으므로,
    /// 저장소 URL을 대상으로 원격 조회를 한 번 수행해 인증 실패를 저장 전에 드러냅니다.
    /// 저장소 URL 자체는 인증 없이 읽을 수 있어 먼저 로컬에서 확인합니다.
    public func verifyCredentials(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws {
        let repositoryURL = try await workingCopyRepositoryURL(at: path, credentials: nil)
        _ = try await checkedRunWithSingleSVNPathArgument(
            ["info", "--show-item", "revision"],
            svnPathArgument: repositoryURL,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
    }

    public func recoveryPreview(
        at path: String,
        credentials: SVNCredentials? = nil
    ) async throws -> SVNRecoveryPreview {
        let snapshot = try await workingCopySnapshot(at: path, credentials: credentials)
        return SVNWorkingCopyRecovery.preview(sourcePath: path, snapshot: snapshot)
    }

    public func recoverWorkingCopy(
        from sourcePath: String,
        to destinationPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> SVNRecoveryResult {
        let source = URL(fileURLWithPath: sourcePath, isDirectory: true).standardizedFileURL
        let destination = URL(fileURLWithPath: destinationPath, isDirectory: true).standardizedFileURL
        try SVNWorkingCopyRecovery.requireSeparateDestination(source: source, destination: destination)
        let preparation = try SVNWorkingCopyRecovery.prepareEmptyDestination(destination)

        do {
            let sourceSnapshot = try await workingCopySnapshot(at: source.path, credentials: credentials)
            let preview = SVNWorkingCopyRecovery.preview(sourcePath: source.path, snapshot: sourceSnapshot)
            guard preview.blockingPaths.isEmpty else {
                throw SVNError.recoveryBlocked(paths: preview.blockingPaths)
            }
            let repositoryURL = try await workingCopyRepositoryURL(at: source.path, credentials: credentials)
            // 원본의 BASE 리비전으로 체크아웃합니다. HEAD로 받으면 그 사이 올라온 커밋이
            // 새 작업 복사본의 BASE가 되어, 복구한 파일을 커밋할 때 out-of-date 검사가
            // 걸리지 않고 다른 사람의 변경이 조용히 사라집니다.
            _ = try await checkout(
                repositoryURL: repositoryURL,
                destinationPath: destination.path,
                revision: sourceSnapshot.revision.minimum,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            )
            try await pinRecoveryBaseRevisions(
                of: sourceSnapshot,
                at: destination.path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            )
            try SVNWorkingCopyRecovery.apply(preview, from: source, to: destination)

            let recoveredSnapshot = try await workingCopySnapshot(at: destination.path, credentials: credentials)
            guard !recoveredSnapshot.hasPathCollisions else {
                throw SVNError.recoveryValidationFailed(paths: recoveredSnapshot.collisions.map(\.displayPath))
            }
            return SVNRecoveryResult(
                destinationPath: destination.path,
                snapshot: recoveredSnapshot,
                migratedPaths: preview.mappings.map(\.destinationPath)
            )
        } catch {
            // 부분 체크아웃이 남으면 같은 폴더로 다시 시도할 때 "비어 있어야 합니다"로만 막힙니다.
            SVNWorkingCopyRecovery.rollbackDestination(preparation, at: destination)
            throw error
        }
    }

    /// 혼합 리비전 작업 복사본은 경로마다 BASE가 다릅니다. 가장 낮은 리비전으로 체크아웃한
    /// 새 작업 복사본에서 더 높은 BASE를 가진 경로만 원본과 같은 리비전으로 올려, 커밋 시
    /// out-of-date 판정이 원본과 동일하게 나오도록 맞춥니다.
    private func pinRecoveryBaseRevisions(
        of snapshot: SVNWorkingCopySnapshot,
        at destinationPath: String,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure>
    ) async throws {
        let baseRevision = snapshot.revision.minimum
        // 상위 경로가 먼저 존재해야 하위 경로를 받을 수 있으므로 깊이 오름차순으로 처리합니다.
        let pending = snapshot.baseRevisionsByPath
            .filter { $0.value != baseRevision && Int($0.value) != nil }
            .map { (path: $0.key.rawPath, revision: $0.value) }
            .sorted {
                let leftDepth = $0.path.split(separator: "/").count
                let rightDepth = $1.path.split(separator: "/").count
                if leftDepth != rightDepth { return leftDepth < rightDepth }
                return $0.path < $1.path
            }
        guard !pending.isEmpty else { return }

        var index = pending.startIndex
        while index < pending.endIndex {
            let revision = pending[index].revision
            var end = index
            while end < pending.endIndex, pending[end].revision == revision { end += 1 }
            let paths = pending[index ..< end].map(\.path)
            _ = try await checkedRunWithSVNPathArguments(
                ["update", "--revision", revision, "--depth", "empty"],
                svnPathArguments: paths,
                escapePegSyntax: Array(repeating: true, count: paths.count),
                at: destinationPath,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            )
            index = end
        }
    }

    public func status(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNStatusEntry] {
        let result = try await checkedRun(["status", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.statuses(from: Data(result.output.utf8))
    }

    public func cleanup(
        at path: String,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try await checkedRun(["cleanup"], at: path, credentials: credentials).output
    }

    public func workingCopyEntries(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNWorkingCopyEntry] {
        let result = try await checkedRun(["status", "--verbose", "--no-ignore", "--xml"], at: path, credentials: credentials)
        let entries = try SVNXMLParser.workingCopyEntries(from: Data(result.output.utf8))
        let snapshot = try SVNWorkingCopySnapshot(entries: entries)
        let resolution = await canonicalFileReplacementResolution(
            in: snapshot,
            at: path,
            credentials: credentials
        )
        return Self.resolvedWorkingCopyEntries(
            entries,
            replacements: snapshot.canonicalFileReplacements,
            resolution: resolution
        )
    }

    public func workingCopySnapshot(at path: String, credentials: SVNCredentials? = nil) async throws -> SVNWorkingCopySnapshot {
        let snapshot = try await readWorkingCopySnapshot(at: path, credentials: credentials)
        let cleanedSnapshot = await cleanupMissingScheduledAdditions(
            in: snapshot,
            at: path,
            credentials: credentials
        )
        let resolvedSnapshot = await resolveCanonicalFileReplacements(
            in: cleanedSnapshot,
            at: path,
            credentials: credentials
        )
        return Self.annotateLocalNodeKinds(in: resolvedSnapshot, at: path)
    }

    private func readWorkingCopySnapshot(
        at path: String,
        credentials: SVNCredentials?
    ) async throws -> SVNWorkingCopySnapshot {
        let result = try await checkedRun(["status", "--verbose", "--no-ignore", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.workingCopySnapshot(from: Data(result.output.utf8))
    }

    private func cleanupMissingScheduledAdditions(
        in snapshot: SVNWorkingCopySnapshot,
        at path: String,
        credentials: SVNCredentials?
    ) async -> SVNWorkingCopySnapshot {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        var current = snapshot

        for missingAdditionPath in snapshot.missingScheduledAdditionCleanupTargets {
            let missingAdditionPathBytes = Data(missingAdditionPath.utf8)
            guard current.missingScheduledAdditionCleanupTargets.contains(where: {
                Data($0.utf8) == missingAdditionPathBytes
            }) else { continue }
            guard !Self.pathEntryExists(at: root.appendingPathComponent(missingAdditionPath)) else { continue }

            do {
                _ = try await checkedRunWithMultipleWorkingCopyPathArguments(
                    ["revert", "--depth", "infinity"],
                    projectRelativePaths: [missingAdditionPath],
                    at: path,
                    credentials: credentials
                )
                current = try await readWorkingCopySnapshot(at: path, credentials: credentials)
            } catch {
                return (try? await readWorkingCopySnapshot(at: path, credentials: credentials)) ?? current
            }
        }
        return current
    }

    private static func pathEntryExists(at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return true }
            var information = stat()
            return Darwin.lstat(path, &information) == 0
        }
    }

    private static func nodeKind(at url: URL) -> SVNNodeKind? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var information = stat()
            guard Darwin.lstat(path, &information) == 0 else { return nil }
            switch information.st_mode & S_IFMT {
            case S_IFREG: return .file
            case S_IFDIR: return .directory
            default: return nil
            }
        }
    }

    private static func annotateLocalNodeKinds(
        in snapshot: SVNWorkingCopySnapshot,
        at workingCopyPath: String
    ) -> SVNWorkingCopySnapshot {
        let root = URL(fileURLWithPath: workingCopyPath, isDirectory: true)
        let kinds: [SVNPathIdentity: SVNNodeKind] = Dictionary(
            uniqueKeysWithValues: snapshot.statuses.compactMap { entry in
                guard let kind = nodeKind(at: root.appendingPathComponent(entry.path)) else { return nil }
                return (SVNPathIdentity(rawPath: entry.path), kind)
            }
        )
        return snapshot.annotatingNodeKinds(kinds)
    }

    private func resolveCanonicalFileReplacements(
        in snapshot: SVNWorkingCopySnapshot,
        at path: String,
        credentials: SVNCredentials?
    ) async -> SVNWorkingCopySnapshot {
        let resolution = await canonicalFileReplacementResolution(
            in: snapshot,
            at: path,
            credentials: credentials
        )
        return snapshot.resolvingCanonicalFileReplacements(
            modifiedPaths: Set(resolution.modified.map(\.rawPath)),
            unchangedPaths: Set(resolution.unchanged.map(\.rawPath))
        )
    }

    private struct CanonicalFileReplacementResolution {
        var modified: Set<SVNPathIdentity> = []
        var unchanged: Set<SVNPathIdentity> = []
    }

    private func canonicalFileReplacementResolution(
        in snapshot: SVNWorkingCopySnapshot,
        at path: String,
        credentials: SVNCredentials?
    ) async -> CanonicalFileReplacementResolution {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        var resolution = CanonicalFileReplacementResolution()

        for replacement in snapshot.canonicalFileReplacements {
            let localURL = root.appendingPathComponent(replacement.localAliasPath)
            guard let values = try? localURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            let baseDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("svn-mac-base-\(UUID().uuidString)", isDirectory: true)
            let baseURL = baseDirectory.appendingPathComponent("base", isDirectory: false)
            do {
                try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: baseDirectory) }
                _ = try await checkedRunWithSingleWorkingCopyPathArgument(
                      ["cat", "--revision", "BASE"],
                      projectRelativePath: replacement.versionedPath,
                      at: path,
                      credentials: credentials,
                      outputDestinationURL: baseURL
                  )
                let versionedIdentity = SVNPathIdentity(rawPath: replacement.versionedPath)
                if try SVNFileSystem.filesHaveEqualContents(localURL, baseURL) {
                    resolution.unchanged.insert(versionedIdentity)
                } else {
                    resolution.modified.insert(versionedIdentity)
                }
            } catch {
                // BASE를 읽지 못하면 내용이 같은지 알 수 없습니다. 여기서 물러나면
                // 디스크에 있는 파일이 "누락"으로 남아 사용자가 되돌리기로 편집을
                // 지울 수 있으므로, 보수적으로 수정된 것으로 표시합니다.
                resolution.modified.insert(SVNPathIdentity(rawPath: replacement.versionedPath))
            }
        }

        return resolution
    }

    private static func resolvedWorkingCopyEntries(
        _ entries: [SVNWorkingCopyEntry],
        replacements: [SVNCanonicalFileReplacement],
        resolution: CanonicalFileReplacementResolution
    ) -> [SVNWorkingCopyEntry] {
        let resolvedVersioned = resolution.modified.union(resolution.unchanged)
        let resolvedReplacements = replacements.filter {
            resolvedVersioned.contains(SVNPathIdentity(rawPath: $0.versionedPath))
        }
        let versionedIdentities = Set(resolvedReplacements.map {
            SVNPathIdentity(rawPath: $0.versionedPath)
        })
        let replacementsByLocalAlias = Dictionary(uniqueKeysWithValues: resolvedReplacements.map {
            (SVNPathIdentity(rawPath: $0.localAliasPath), $0)
        })

        return entries.compactMap { entry in
            let identity = SVNPathIdentity(rawPath: entry.path)
            if versionedIdentities.contains(identity) {
                return nil
            }
            guard let replacement = replacementsByLocalAlias[identity] else {
                return entry
            }
            let status = resolution.modified.contains(
                SVNPathIdentity(rawPath: replacement.versionedPath)
            ) ? "modified" : "normal"
            return SVNWorkingCopyEntry(
                path: entry.path,
                status: status,
                revision: replacement.revision,
                treeConflicted: entry.treeConflicted,
                repositoryPath: replacement.versionedPath
            )
        }
    }

    public func repairCanonicalAliases(
        at path: String,
        credentials: SVNCredentials? = nil
    ) async throws -> SVNWorkingCopySnapshot {
        let before = try await workingCopySnapshot(at: path, credentials: credentials)
        return try await repairCanonicalAliases(
            in: before,
            at: path,
            credentials: credentials
        )
    }

    private func repairCanonicalAliases(
        in before: SVNWorkingCopySnapshot,
        at path: String,
        credentials: SVNCredentials?
    ) async throws -> SVNWorkingCopySnapshot {
        guard !before.hasUnrepairablePathCollisions else {
            throw SVNError.pathNormalizationCollision(paths: before.collisions.map(\.displayPath))
        }
        let canonicalAliasRepairPaths = before.canonicalAliasRepairTargets
        if !canonicalAliasRepairPaths.isEmpty {
            _ = try await checkedRunWithMultipleWorkingCopyPathArguments(
                ["revert", "--depth", "empty"],
                projectRelativePaths: canonicalAliasRepairPaths,
                at: path,
                credentials: credentials
            )
        }
        let after = try await workingCopySnapshot(at: path, credentials: credentials)
        guard !after.hasUnrepairablePathCollisions else {
            throw SVNError.pathNormalizationCollision(paths: after.collisions.map(\.displayPath))
        }
        guard !after.hasPathCollisions else {
            throw SVNError.pathAliasRepairFailed(paths: after.collisions.map(\.displayPath))
        }
        return after
    }

    public func ignoredStatus(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNStatusEntry] {
        let result = try await checkedRun(["status", "--no-ignore", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.statuses(from: Data(result.output.utf8)).filter { $0.item == .ignored }
    }

    public func ignoreRules(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNIgnoreRule] {
        var rules: [SVNIgnoreRule] = []
        for kind in [SVNIgnorePropertyKind.local, .global] {
            let result = try await run(
                ["propget", kind.propertyName, "--recursive", "--show-inherited-props", "--xml", "."],
                at: path,
                credentials: credentials
            )
            if result.exitCode != 0, result.error.contains("W200017") { continue }
            guard result.exitCode == 0 else {
                throw SVNError.commandFailed(command: "svn propget \(kind.propertyName)", message: result.error)
            }
            rules += try SVNXMLParser.ignoreRules(from: Data(result.output.utf8))
        }
        return rules.sorted {
            ($0.directory, $0.propertyKind.rawValue, $0.pattern)
                < ($1.directory, $1.propertyKind.rawValue, $1.pattern)
        }
    }

    public func addIgnoreRule(
        at path: String,
        directory: String,
        pattern: String,
        propertyKind: SVNIgnorePropertyKind = .local,
        credentials: SVNCredentials? = nil
    ) async throws {
        let existing = try await ignorePatterns(
            at: path,
            directory: directory,
            propertyKind: propertyKind,
            credentials: credentials
        )
        let alignedPattern = Self.ignorePatternMatchingWorkingCopyEntry(
            pattern,
            inProjectRelativeDirectory: directory,
            at: path
        )
        guard !existing.contains(alignedPattern) else { return }
        try await setIgnorePatterns(
            existing + [alignedPattern],
            at: path,
            directory: directory,
            propertyKind: propertyKind,
            credentials: credentials
        )
    }

    /// svn의 무시 판정은 이름 바이트 비교입니다. `.gitignore`처럼 외부 파일에서 온
    /// NFC 패턴은 디스크가 NFD로 들고 있는 한글 이름과 매칭되지 않아 아무것도 무시하지
    /// 못합니다. 같은 NFC 키를 가진 실제 항목이 있으면 그 항목의 원문 바이트로 맞춥니다.
    /// glob 패턴과 아직 존재하지 않는 이름은 맞출 대상이 없으므로 원문 그대로 둡니다.
    static func ignorePatternMatchingWorkingCopyEntry(
        _ pattern: String,
        inProjectRelativeDirectory directory: String,
        at localProjectPath: String
    ) -> String {
        guard pattern.unicodeScalars.contains(where: { !$0.isASCII }) else { return pattern }
        let projectRoot = URL(fileURLWithPath: localProjectPath, isDirectory: true)
        let directoryURL = directory.isEmpty || directory == "."
            ? projectRoot
            : projectRoot.appendingPathComponent(directory, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path) else {
            return pattern
        }
        let patternBytes = Data(pattern.utf8)
        let canonicalPattern = pattern.precomposedStringWithCanonicalMapping
        let alias = names.first {
            Data($0.utf8) != patternBytes
                && $0.precomposedStringWithCanonicalMapping == canonicalPattern
        }
        return alias ?? pattern
    }

    public func removeIgnoreRule(
        at path: String,
        directory: String,
        pattern: String,
        propertyKind: SVNIgnorePropertyKind = .local,
        credentials: SVNCredentials? = nil
    ) async throws {
        let remaining = try await ignorePatterns(
            at: path,
            directory: directory,
            propertyKind: propertyKind,
            credentials: credentials
        )
            .filter { $0 != pattern }
        if remaining.isEmpty {
            _ = try await checkedRunWithSingleWorkingCopyPathArgument(
                ["propdel", propertyKind.propertyName],
                projectRelativePath: directory,
                at: path,
                credentials: credentials
            )
        } else {
            try await setIgnorePatterns(
                remaining,
                at: path,
                directory: directory,
                propertyKind: propertyKind,
                credentials: credentials
            )
        }
    }

    private func setIgnorePatterns(
        _ patterns: [String],
        at path: String,
        directory: String,
        propertyKind: SVNIgnorePropertyKind,
        credentials: SVNCredentials?
    ) async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-property-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let valueURL = temporaryDirectory.appendingPathComponent("value", isDirectory: false)
        try Data((patterns.joined(separator: "\n") + "\n").utf8)
            .write(to: valueURL, options: .atomic)
        _ = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["propset", propertyKind.propertyName, "--file", valueURL.path],
            projectRelativePath: directory,
            at: path,
            credentials: credentials
        )
    }

    public func scheduleDeletion(
        at path: String,
        paths: [String],
        credentials: SVNCredentials? = nil
    ) async throws -> SVNDeletionResult {
        let snapshot = try await workingCopySnapshot(at: path, credentials: credentials)
        guard !snapshot.hasPathCollisions else {
            throw SVNError.pathNormalizationCollision(paths: snapshot.collisions.map(\.displayPath))
        }

        let resolvedPaths = try paths.map { selectedPath -> String in
            guard let resolved = snapshot.resolvedPath(for: selectedPath) else {
                throw SVNError.pathNormalizationCollision(
                    paths: [selectedPath.precomposedStringWithCanonicalMapping]
                )
            }
            return resolved
        }
        let statusByCanonicalPath = Dictionary(
            uniqueKeysWithValues: snapshot.statuses.map {
                (SVNPathIdentity(rawPath: $0.path), $0)
            }
        )
        let invalidPaths = resolvedPaths.filter {
            statusByCanonicalPath[SVNPathIdentity(rawPath: $0)]?.canScheduleRepositoryDeletion != true
        }
        guard invalidPaths.isEmpty else {
            throw SVNError.unresolvedMissingPaths(paths: invalidPaths)
        }

        let targets = Self.normalizedCommitPaths(resolvedPaths)
        _ = try await checkedRunWithMultipleWorkingCopyPathArguments(
            ["delete", "--force"],
            projectRelativePaths: targets,
            at: path,
            credentials: credentials
        )

        let after = try await workingCopySnapshot(at: path, credentials: credentials)
        let deletedCanonicalPaths = Set(after.statuses.lazy.filter { $0.item == .deleted }.map {
            SVNPathIdentity(rawPath: $0.path)
        })
        let failed = targets.filter {
            !deletedCanonicalPaths.contains(SVNPathIdentity(rawPath: $0))
        }
        guard failed.count < targets.count else {
            throw SVNError.deletionValidationFailed(paths: failed)
        }
        let scheduled = targets.filter { !failed.contains($0) }
        return SVNDeletionResult(scheduledPaths: scheduled, failedPaths: failed)
    }

    /// 내용 검증과 사용자 확인을 마친 저장소 임시파일 하나를 삭제 예약합니다.
    /// 일반 누락 항목 삭제와 달리 update 직후 디스크에 존재하는 버전관리 항목이 대상입니다.
    public func scheduleRepositoryCleanupDeletion(
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil
    ) async throws {
        let snapshot = try await workingCopySnapshot(at: path, credentials: credentials)
        guard !snapshot.hasPathCollisions,
              let resolvedPath = snapshot.resolvedPath(for: relativePath) else {
            throw SVNError.pathNormalizationCollision(paths: [relativePath])
        }

        _ = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["delete", "--force"],
            projectRelativePath: resolvedPath,
            at: path,
            credentials: credentials
        )

        let after = try await workingCopySnapshot(at: path, credentials: credentials)
        guard after.statuses.contains(where: {
            SVNPathIdentity(rawPath: $0.path) == SVNPathIdentity(rawPath: resolvedPath)
                && $0.item == .deleted
        }) else {
            throw SVNError.deletionValidationFailed(paths: [relativePath])
        }
    }

    public func repositoryLocks(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNLockInfo] {
        let result = try await checkedRun(
            ["status", "--show-updates", "--xml"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.repositoryLocks(fromStatus: Data(result.output.utf8))
    }

    public func lockInfo(
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> SVNLockInfo? {
        let result = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["info", "--xml", "--revision", "HEAD"],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.repositoryLock(fromInfo: Data(result.output.utf8))
    }

    public func lock(
        at path: String,
        relativePath: String,
        comment: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        try await withSVNLogMessageFile(comment) { messageFilePath in
            try await checkedRunWithSingleWorkingCopyPathArgument(
                ["lock", "--file", messageFilePath, "--force-log"],
                projectRelativePath: relativePath,
                at: path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            ).output
        }
    }

    public func lock(
        at path: String,
        relativePaths: [String],
        comment: String,
        force: Bool = false,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        try await withSVNLogMessageFile(comment) { messageFilePath in
            var arguments = ["lock", "--file", messageFilePath, "--force-log"]
            if force { arguments.append("--force") }
            return try await checkedRunWithMultipleWorkingCopyPathArguments(
                arguments,
                projectRelativePaths: relativePaths,
                at: path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            ).output
        }
    }

    public func unlock(
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        try await unlock(
            at: path,
            relativePath: relativePath,
            force: false,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
    }

    public func unlock(
        at path: String,
        relativePath: String,
        force: Bool = false,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        var arguments = ["unlock"]
        if force { arguments.append("--force") }
        return try await checkedRunWithSingleWorkingCopyPathArgument(
            arguments,
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ).output
    }

    public func unlock(
        at path: String,
        relativePaths: [String],
        force: Bool = false,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        var arguments = ["unlock"]
        if force { arguments.append("--force") }
        return try await checkedRunWithMultipleWorkingCopyPathArguments(
            arguments,
            projectRelativePaths: relativePaths,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ).output
    }

    /// 등록 프로젝트가 작업 복사본의 하위 폴더여도 파일 명령은 `.svn`이 있는
    /// 루트에서 실행합니다. 프로젝트 폴더의 로컬 표기(NFD일 수 있음)를 그대로
    /// 붙이지 않고 SVN이 실제로 관리하는 원문 표기를 판별해 경로를 구성합니다.
    private func resolveWorkingCopyCommandPath(
        localProjectPath: String,
        projectRelativePath: String,
        credentials: SVNCredentials?
    ) async throws -> SVNWorkingCopyCommandPath {
        let localProjectURL = URL(fileURLWithPath: localProjectPath, isDirectory: true).standardizedFileURL
        guard let workingCopyRootURL = findWorkingCopyRootURL(containing: localProjectURL) else {
            return SVNWorkingCopyCommandPath(
                workingCopyRootPath: localProjectPath,
                svnProjectPathPrefixRelativeToWorkingCopyRoot: "",
                svnPathRelativeToWorkingCopyRoot: projectRelativePath
            )
        }

        let localProjectPrefix = localProjectURL.pathComponents
            .dropFirst(workingCopyRootURL.pathComponents.count)
            .joined(separator: "/")
        guard !localProjectPrefix.isEmpty else {
            return SVNWorkingCopyCommandPath(
                workingCopyRootPath: workingCopyRootURL.path,
                svnProjectPathPrefixRelativeToWorkingCopyRoot: "",
                svnPathRelativeToWorkingCopyRoot: projectRelativePath
            )
        }

        let svnProjectPathPrefix = try await resolveSVNProjectPathPrefix(
            localProjectPrefix: localProjectPrefix,
            localProjectPath: localProjectPath,
            workingCopyRootPath: workingCopyRootURL.path,
            credentials: credentials
        )
        let svnPathRelativeToWorkingCopyRoot = projectRelativePath == "."
            ? svnProjectPathPrefix
            : svnProjectPathPrefix + "/" + projectRelativePath
        return SVNWorkingCopyCommandPath(
            workingCopyRootPath: workingCopyRootURL.path,
            svnProjectPathPrefixRelativeToWorkingCopyRoot: svnProjectPathPrefix,
            svnPathRelativeToWorkingCopyRoot: svnPathRelativeToWorkingCopyRoot
        )
    }

    /// 같은 한글 이름이라도 SVN 저장소에는 NFC 또는 NFD 원문이 들어 있을 수
    /// 있습니다. 경로 구성요소마다 로컬 표기와 NFC 후보를 `svn info`로 확인해
    /// 상위 NFC/하위 NFD처럼 표기가 섞인 경로도 정확히 조립한 뒤 캐시합니다.
    private func resolveSVNProjectPathPrefix(
        localProjectPrefix: String,
        localProjectPath: String,
        workingCopyRootPath: String,
        credentials: SVNCredentials?
    ) async throws -> String {
        let localProjectPathIdentity = SVNPathIdentity(rawPath: localProjectPath)
        let metadataModificationDate = workingCopyMetadataModificationDate(
            at: workingCopyRootPath
        )
        if let cached = svnProjectPathPrefixByLocalProjectPath[localProjectPathIdentity],
           cached.workingCopyMetadataModificationDate == metadataModificationDate {
            return cached.prefix
        }

        var resolvedSVNPathComponents: [String] = []
        for localPathComponent in localProjectPrefix.split(separator: "/").map(String.init) {
            let precomposedPathComponent = localPathComponent.precomposedStringWithCanonicalMapping
            let svnPathComponentCandidates = [localPathComponent, precomposedPathComponent]
                .reduce(into: [String]()) { components, candidateComponent in
                    guard !components.contains(where: {
                        Data($0.utf8) == Data(candidateComponent.utf8)
                    }) else { return }
                    components.append(candidateComponent)
                }
            let candidateSVNPaths = svnPathComponentCandidates.map {
                (resolvedSVNPathComponents + [$0]).joined(separator: "/")
            }
            let unsafeProjectPaths = Self.svnPathsUnsafeForLineDelimitedTransport(
                candidateSVNPaths
            )
            guard unsafeProjectPaths.isEmpty else {
                throw SVNError.unsupportedTargetPath(paths: unsafeProjectPaths)
            }

            var resolvedSVNPathComponent: String?
            for (candidateComponent, candidateSVNPath) in zip(
                svnPathComponentCandidates,
                candidateSVNPaths
            ) {
                let infoResult = try await run(
                    ["info", "--show-item", "kind"],
                    svnPathArgument: Self.svnPathEscapingPegSyntax(candidateSVNPath),
                    at: workingCopyRootPath,
                    credentials: credentials
                )
                if infoResult.exitCode == 0 {
                    resolvedSVNPathComponent = candidateComponent
                    break
                }
            }
            guard let resolvedSVNPathComponent else {
                // 판별 실패 시 호출 명령이 SVN의 구체적인 오류를 표시하도록
                // 원래 로컬 표기로 실행하며, 불확실한 값은 캐시하지 않습니다.
                return localProjectPrefix
            }
            resolvedSVNPathComponents.append(resolvedSVNPathComponent)
        }

        let svnProjectPathPrefix = resolvedSVNPathComponents.joined(separator: "/")
        svnProjectPathPrefixByLocalProjectPath[localProjectPathIdentity] =
            ProjectPathPrefixCacheEntry(
                prefix: svnProjectPathPrefix,
                workingCopyMetadataModificationDate: metadataModificationDate
            )
        return svnProjectPathPrefix
    }

    private func workingCopyMetadataModificationDate(at workingCopyRootPath: String) -> Date? {
        let metadataPath = URL(fileURLWithPath: workingCopyRootPath, isDirectory: true)
            .appendingPathComponent(".svn", isDirectory: true)
            .appendingPathComponent("wc.db", isDirectory: false)
            .path
        return try? FileManager.default.attributesOfItem(atPath: metadataPath)[.modificationDate] as? Date
    }

    private func findWorkingCopyRootURL(containing localURL: URL) -> URL? {
        var candidateDirectoryURL = localURL
        while candidateDirectoryURL.path != "/" {
            let svnMetadataURL = candidateDirectoryURL.appendingPathComponent(".svn", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: svnMetadataURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidateDirectoryURL
            }
            candidateDirectoryURL.deleteLastPathComponent()
        }
        return nil
    }

    public func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials? = nil) async throws -> SVNConflictDetails? {
        let commandPath = try await resolveWorkingCopyCommandPath(
            localProjectPath: path,
            projectRelativePath: relativePath,
            credentials: credentials
        )
        let result = try await checkedRunWithSingleSVNPathArgument(
            ["info", "--xml"],
            svnPathArgument: commandPath.svnPathRelativeToWorkingCopyRoot,
            at: commandPath.workingCopyRootPath,
            credentials: credentials
        )
        guard let workingCopyRootConflictDetails = try SVNXMLParser.conflictDetails(
            fromInfo: Data(result.output.utf8)
        ) else { return nil }

        // 명령을 작업 복사본 루트에서 실행하면 SVN XML의 entry/artifact 경로도
        // 루트 기준으로 반환됩니다. ConflictFileService는 등록 프로젝트 경로를
        // 기준으로 파일을 찾으므로 프로젝트 접두사를 제거해 기존 계약을 지킵니다.
        return Self.conflictDetailsRelativeToRegisteredProject(
            workingCopyRootConflictDetails,
            svnProjectPathPrefix: commandPath.svnProjectPathPrefixRelativeToWorkingCopyRoot
        )
    }

    static func conflictDetailsRelativeToRegisteredProject(
        _ conflictDetails: SVNConflictDetails,
        svnProjectPathPrefix: String
    ) -> SVNConflictDetails {
        guard !svnProjectPathPrefix.isEmpty else { return conflictDetails }

        func projectRelativeConflictPath(_ workingCopyRootRelativePath: String?) -> String? {
            guard let workingCopyRootRelativePath else { return nil }
            let projectPathPrefixWithSeparator = svnProjectPathPrefix + "/"
            guard workingCopyRootRelativePath.hasPrefix(projectPathPrefixWithSeparator) else {
                // SVN 버전이나 충돌 유형에 따라 절대 경로가 올 수 있으므로,
                // 확인된 프로젝트 접두사로 시작하는 상대 경로만 변경합니다.
                return workingCopyRootRelativePath
            }
            return String(workingCopyRootRelativePath.dropFirst(projectPathPrefixWithSeparator.count))
        }

        return SVNConflictDetails(
            path: projectRelativeConflictPath(conflictDetails.path) ?? conflictDetails.path,
            type: conflictDetails.type,
            operation: conflictDetails.operation,
            previousBaseFile: projectRelativeConflictPath(conflictDetails.previousBaseFile),
            myFile: projectRelativeConflictPath(conflictDetails.myFile),
            serverFile: projectRelativeConflictPath(conflictDetails.serverFile),
            previousRevision: conflictDetails.previousRevision,
            serverRevision: conflictDetails.serverRevision
        )
    }

    public func resolveConflict(
        at path: String,
        relativePath: String,
        choice: SVNConflictChoice,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try await checkedRunWithSingleWorkingCopyPathArgument(
            ["resolve", "--accept", choice.rawValue],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials
        ).output
    }

    public func log(
        at path: String,
        limit: Int = 50,
        endingAtRevision: String? = nil,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNLogEntry] {
        let revisionRange = "\(endingAtRevision ?? "HEAD"):1"
        let result = try await checkedRun(
            ["log", "--xml", "--verbose", "--with-all-revprops", "--revision", revisionRange, "--limit", String(limit)],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.logs(from: Data(result.output.utf8))
    }

    public func revisionDiff(
        at path: String,
        revision: String,
        repositoryPath: String,
        workingCopyRepositoryPath: String?,
        pegRevision: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        let repositoryRevisionPath = revisionTargetPath(
            repositoryPath: repositoryPath,
            workingCopyRepositoryPath: workingCopyRepositoryPath
        )
        let repositoryRevisionPathArgument = "^\(repositoryRevisionPath)@\(pegRevision)"
        return try await checkedRunWithSingleSVNPathArgument(
            ["diff", "--change", revision],
            svnPathArgument: repositoryRevisionPathArgument,
            escapePegSyntax: false,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ).output
    }

    /// 로그 경로의 작업 복사본 root만 `svn info relative-url`이 반환한 실제
    /// 서버 경로로 교체합니다. root 아래의 이름은 원문을 보존해야 저장소에
    /// NFD 이름으로 남아 있는 과거 파일도 해당 리비전에서 조회할 수 있습니다.
    private func revisionTargetPath(repositoryPath: String, workingCopyRepositoryPath: String?) -> String {
        let repositoryPath = repositoryPath.hasPrefix("/") ? repositoryPath : "/\(repositoryPath)"
        guard let workingCopyRepositoryPath, !workingCopyRepositoryPath.isEmpty else {
            return Self.repositoryPathEscapingLiteralPercents(repositoryPath)
        }

        let rootPath = workingCopyRepositoryPath.hasPrefix("/")
            ? workingCopyRepositoryPath
            : "/\(workingCopyRepositoryPath)"
        let decodedRootPath = rootPath.removingPercentEncoding ?? rootPath
        let repositoryComponents = pathComponents(repositoryPath)
        let rootComponents = pathComponents(decodedRootPath)
        guard repositoryComponents.starts(with: rootComponents) else {
            return Self.repositoryPathEscapingLiteralPercents(repositoryPath)
        }

        let suffix = repositoryComponents.dropFirst(rootComponents.count)
            .map { $0.replacingOccurrences(of: "%", with: "%25") }
            .joined(separator: "/")
        let encodedRoot = rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = [encodedRoot, suffix].filter { !$0.isEmpty }
        return "/" + components.joined(separator: "/")
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public func workingCopyRevision(at path: String, credentials: SVNCredentials? = nil) async throws -> SVNWorkingCopyRevision {
        let result = try await checkedRun(["status", "--verbose", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.workingCopyRevision(from: Data(result.output.utf8))
    }

    /// 작업 복사본 루트가 저장소 루트 아래에서 차지하는 경로를 반환합니다.
    /// `svn log --verbose`의 변경 경로는 저장소 루트 기준 절대 경로이므로,
    /// 화면에서 로컬 프로젝트 루트 기준 경로로 줄여 표시할 때 이 값이 필요합니다.
    public func workingCopyRepositoryPath(at path: String, credentials: SVNCredentials? = nil) async throws -> String {
        let relativeURL = try await checkedRun(
            ["info", "--show-item", "relative-url"],
            at: path,
            credentials: credentials
        )
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard relativeURL.hasPrefix("^/") else { return relativeURL }
        return "/" + relativeURL.dropFirst(2)
    }

    public func incomingCommits(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNLogEntry] {
        let baseRevision = try await workingCopyRevision(at: path, credentials: credentials)
        guard let base = Int(baseRevision.minimum) else { throw SVNError.malformedResponse }
        let headResult = try await checkedRun(
            ["info", "--revision", "HEAD", "--show-item", "revision"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        guard let head = Int(headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SVNError.malformedResponse
        }
        guard head > base else { return [] }
        let result = try await checkedRun(
            [
                "log", "--revision", "\(base + 1):HEAD", "--verbose", "--xml",
                "--with-all-revprops",
            ],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        let logs = try SVNXMLParser.logs(from: Data(result.output.utf8))
        guard logs.contains(where: { !$0.changedPaths.isEmpty }) else { return logs }
        let workingCopyRepositoryPath = try await workingCopyRepositoryPath(
            at: path,
            credentials: credentials
        )
        let remoteChanges = try await remoteChanges(
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        guard !remoteChanges.isEmpty else { return [] }
        let remotePaths = remoteChanges.map(\.path)
        return logs.filter { entry in
            entry.changedPaths.contains { changedPath in
                guard let relativePath = projectRelativePath(
                    changedPath.path,
                    workingCopyRepositoryPath: workingCopyRepositoryPath
                ) else { return false }
                return remotePaths.contains { Self.pathsOverlap(relativePath, $0) }
            }
        }
    }

    private func projectRelativePath(
        _ repositoryPath: String,
        workingCopyRepositoryPath: String
    ) -> String? {
        let repositoryComponents = pathComponents(repositoryPath)
        let rootPath = workingCopyRepositoryPath.removingPercentEncoding
            ?? workingCopyRepositoryPath
        let rootComponents = pathComponents(rootPath)
        guard repositoryComponents.starts(with: rootComponents) else { return nil }
        let relativeComponents = repositoryComponents.dropFirst(rootComponents.count)
        return relativeComponents.isEmpty ? "." : relativeComponents.joined(separator: "/")
    }

    private static func pathsOverlap(_ first: String, _ second: String) -> Bool {
        if first == "." || second == "." { return true }
        return first == second
            || first.hasPrefix(second + "/")
            || second.hasPrefix(first + "/")
    }

    public func workingCopyIsOutOfDate(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> Bool {
        let result = try await checkedRun(
            ["status", "--show-updates", "--xml"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.workingCopyIsOutOfDate(from: Data(result.output.utf8))
    }

    public func remoteChanges(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNStatusEntry] {
        let result = try await checkedRun(
            ["status", "--show-updates", "--xml"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.remoteChanges(from: Data(result.output.utf8))
    }

    public func update(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        try await checkedRun(
            ["update"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        ).output
    }

    public func diff(at path: String, relativePath: String? = nil, credentials: SVNCredentials? = nil) async throws -> String {
        guard let relativePath else {
            return try await checkedRun(["diff"], at: path, credentials: credentials).output
        }
        return try await checkedRunWithSingleWorkingCopyPathArgument(
            ["diff"],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials
        ).output
    }

    public func revert(at path: String, relativePath: String, credentials: SVNCredentials? = nil) async throws -> String {
        try await checkedRunWithSingleWorkingCopyPathArgument(
            ["revert", "--depth", "infinity"],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials
        ).output
    }

    public func fileLog(
        at path: String,
        relativePath: String,
        limit: Int = 100,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> [SVNLogEntry] {
        let result = try await checkedRunWithSingleWorkingCopyPathArgument(
            ["log", "--xml", "--verbose", "--with-all-revprops", "--limit", String(limit)],
            projectRelativePath: relativePath,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        return try SVNXMLParser.logs(from: Data(result.output.utf8))
    }

    public func commit(
        at path: String,
        paths: [String],
        message: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> String {
        guard !paths.isEmpty else {
            throw SVNClientArgumentError.emptyTargets(command: "commit")
        }
        let messageFile = try Self.makeSVNLogMessageFile(message)
        defer { try? FileManager.default.removeItem(at: messageFile.directory) }

        // 화면을 새로 고친 뒤 파일명이 바뀔 수 있으므로, 변경 명령 직전에 원문 경로를
        // 다시 읽습니다. 기존 SVN 경로의 정확한 바이트 표현을 유지해 macOS의 NFD 경로가
        // 별도 추가 트리로 예약되는 일을 막습니다.
        var snapshot = try await workingCopySnapshot(at: path, credentials: credentials)
        if !snapshot.repairableAliasPaths.isEmpty {
            snapshot = try await repairCanonicalAliases(
                in: snapshot,
                at: path,
                credentials: credentials
            )
        }
        guard !snapshot.hasUnrepairablePathCollisions else {
            throw SVNError.pathNormalizationCollision(paths: snapshot.collisions.map(\.displayPath))
        }

        var resolvedPaths = try paths.map { selectedPath -> String in
            guard let resolved = snapshot.resolvedPath(for: selectedPath) else {
                throw SVNError.pathNormalizationCollision(
                    paths: [selectedPath.precomposedStringWithCanonicalMapping]
                )
            }
            return resolved
        }
        let selectedReplacements = Self.selectedCanonicalFileReplacements(
            in: snapshot,
            selectedPaths: resolvedPaths
        )
        if !selectedReplacements.isEmpty {
            snapshot = try await materializeCanonicalFileReplacements(
                selectedReplacements,
                at: path,
                credentials: credentials
            )
        }
        var currentStatuses = snapshot.statuses
        var statusByPath: [SVNPathIdentity: SVNStatusKind] = [:]
        for status in currentStatuses {
            statusByPath[SVNPathIdentity(rawPath: status.path)] = status.item
        }

        var normalizedPaths = Self.normalizedCommitPaths(resolvedPaths)
        var unresolvedMissingPaths = resolvedPaths.filter {
            statusByPath[SVNPathIdentity(rawPath: $0)] == .missing
        }
        guard unresolvedMissingPaths.isEmpty else {
            throw SVNError.unresolvedMissingPaths(paths: unresolvedMissingPaths)
        }
        var additions = Self.normalizedCommitPaths(resolvedPaths.filter {
            statusByPath[SVNPathIdentity(rawPath: $0)] == .unversioned
        })

        if !additions.isEmpty {
            let pathNormalization = SVNPathNormalization.normalizeNewPaths(
                rootPath: path,
                relativePaths: additions,
                versionedPathsByCanonicalKey: snapshot.versionedPathsByCanonicalKey
            )
            // HFS+처럼 rename 뒤에도 NFD로 되돌리는 볼륨에서는 원문 경로로 add를 계속합니다.
            // NFC 문자열만 넘기면 E155010(추가 예약 경로 누락)이 발생하므로 실패를 삼켜
            // 문자열만 바꾸지 않고, 디스크 rename이 확인된 경우에만 스냅샷을 갱신합니다.
            if pathNormalization.didRename {
                let previousAdditions = additions
                let normalizedAdditions = pathNormalization.normalizedPaths
                func pathAfterNormalization(_ originalPath: String) -> String {
                    let originalBytes = Data(originalPath.utf8)
                    for (previous, normalized) in zip(previousAdditions, normalizedAdditions) {
                        let previousBytes = Data(previous.utf8)
                        if originalBytes == previousBytes { return normalized }
                        let prefixBytes = previousBytes + Data([0x2F])
                        guard originalBytes.starts(with: prefixBytes) else { continue }
                        let suffixBytes = originalBytes.dropFirst(prefixBytes.count)
                        guard let suffix = String(data: suffixBytes, encoding: .utf8) else { continue }
                        return normalized + "/" + suffix
                    }
                    return originalPath
                }

                snapshot = try await workingCopySnapshot(at: path, credentials: credentials)
                guard !snapshot.hasUnrepairablePathCollisions else {
                    throw SVNError.pathNormalizationCollision(
                        paths: snapshot.collisions.map(\.displayPath)
                    )
                }
                resolvedPaths = try resolvedPaths.map { previousPath -> String in
                    let renamedPath = pathAfterNormalization(previousPath)
                    guard let resolved = snapshot.resolvedPath(for: renamedPath) else {
                        throw SVNError.pathNormalizationCollision(
                            paths: [renamedPath.precomposedStringWithCanonicalMapping]
                        )
                    }
                    return resolved
                }
                currentStatuses = snapshot.statuses
                statusByPath.removeAll(keepingCapacity: true)
                for status in currentStatuses {
                    statusByPath[SVNPathIdentity(rawPath: status.path)] = status.item
                }
                normalizedPaths = Self.normalizedCommitPaths(resolvedPaths)
                unresolvedMissingPaths = resolvedPaths.filter {
                    statusByPath[SVNPathIdentity(rawPath: $0)] == .missing
                }
                guard unresolvedMissingPaths.isEmpty else {
                    throw SVNError.unresolvedMissingPaths(paths: unresolvedMissingPaths)
                }
                additions = Self.normalizedCommitPaths(resolvedPaths.filter {
                    statusByPath[SVNPathIdentity(rawPath: $0)] == .unversioned
                })
            }
        }

        var scheduledByThisCommit: [String] = []
        let commitOutput: String
        do {
            if !additions.isEmpty {
                scheduledByThisCommit.append(contentsOf: Self.additionRollbackRoots(
                    additions,
                    versionedPathsByCanonicalKey: snapshot.versionedPathsByCanonicalKey,
                    preexistingScheduledAdditionPaths: snapshot.scheduledAdditionPaths
                ))
                _ = try await checkedRunWithMultipleWorkingCopyPathArguments(
                    ["add", "--parents"],
                    projectRelativePaths: additions,
                    at: path,
                    credentials: credentials
                )
            }
            commitOutput = try await checkedRunWithMultipleWorkingCopyPathArguments(
                ["commit", "--file", messageFile.path, "--force-log"],
                projectRelativePaths: normalizedPaths,
                at: path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate,
                allowedServerCertificateFailures: allowedServerCertificateFailures
            ).output
        } catch {
            let rollbackTargets = Self.normalizedCommitPaths(scheduledByThisCommit)
            if !rollbackTargets.isEmpty {
                _ = try? await checkedRunWithMultipleWorkingCopyPathArguments(
                    ["revert", "--depth", "infinity"],
                    projectRelativePaths: rollbackTargets,
                    at: path,
                    credentials: credentials
                )
            }
            throw error
        }

        // 저장소 커밋이 성공한 뒤의 검증 실패는 add/delete 예약 롤백 범위 밖입니다.
        // 이 시점에 revert하면 이미 서버에 올라간 변경을 사용자가 재시도하게 만들 수
        // 있으므로, 완료 사실과 검증 경고를 함께 전달합니다.
        let committedSnapshot: SVNWorkingCopySnapshot
        do {
            committedSnapshot = try await workingCopySnapshot(at: path, credentials: credentials)
        } catch {
            throw SVNError.commitSucceededWithValidationWarning(
                output: commitOutput,
                details: String(describing: error)
            )
        }
        guard !committedSnapshot.hasPathCollisions else {
            throw SVNError.commitSucceededWithValidationWarning(
                output: commitOutput,
                details: committedSnapshot.collisions.map(\.displayPath).joined(separator: ", ")
            )
        }
        return commitOutput
    }

    private func materializeCanonicalFileReplacements(
        _ replacements: [SVNCanonicalFileReplacement],
        at path: String,
        credentials: SVNCredentials?
    ) async throws -> SVNWorkingCopySnapshot {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: path, isDirectory: true)
        struct BackupRecord {
            let replacement: SVNCanonicalFileReplacement
            let localURL: URL
            let versionedURL: URL
            let directoryURL: URL
            let backupURL: URL
            var aliasWasRemoved: Bool
        }
        var backups: [BackupRecord] = []

        do {
            for replacement in replacements {
                let localURL = root.appendingPathComponent(replacement.localAliasPath)
                let versionedURL = root.appendingPathComponent(replacement.versionedPath)
                let localValues = try localURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard localValues.isRegularFile == true,
                      localValues.isSymbolicLink != true else {
                    throw SVNError.pathAliasRepairFailed(paths: [replacement.versionedPath])
                }
                let backupDirectory = fileManager.temporaryDirectory
                    .appendingPathComponent(
                        "svn-mac-file-replacement-backup-\(UUID().uuidString)",
                        isDirectory: true
                    )
                try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
                let backupURL = backupDirectory.appendingPathComponent("replacement", isDirectory: false)
                backups.append(BackupRecord(
                    replacement: replacement,
                    localURL: localURL,
                    versionedURL: versionedURL,
                    directoryURL: backupDirectory,
                    backupURL: backupURL,
                    aliasWasRemoved: false
                ))
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backupDirectory.path)
                try fileManager.copyItem(at: localURL, to: backupURL)
                guard try SVNFileSystem.filesHaveEqualContents(localURL, backupURL) else {
                    throw SVNError.pathAliasRepairFailed(paths: [replacement.versionedPath])
                }

                let preRemovalValues = try localURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard preRemovalValues.isRegularFile == true,
                      preRemovalValues.isSymbolicLink != true,
                      try SVNFileSystem.filesHaveEqualContents(localURL, backupURL) else {
                    throw SVNError.pathAliasRepairFailed(paths: [replacement.versionedPath])
                }
                try fileManager.removeItem(at: localURL)
                backups[backups.count - 1].aliasWasRemoved = true
                _ = try await checkedRunWithMultipleWorkingCopyPathArguments(
                    ["revert", "--depth", "empty"],
                    projectRelativePaths: [replacement.versionedPath],
                    at: path,
                    credentials: credentials
                )
                try SVNFileSystem.overwriteFile(at: versionedURL, withContentsOf: backupURL)
            }

            let refreshed = try await workingCopySnapshot(at: path, credentials: credentials)
            let statusByPath = Dictionary(
                uniqueKeysWithValues: refreshed.statuses.map {
                    ($0.path.precomposedStringWithCanonicalMapping, $0.item)
                }
            )
            let invalidPaths = replacements.compactMap { replacement -> String? in
                statusByPath[replacement.versionedPath.precomposedStringWithCanonicalMapping] == .modified
                    ? nil
                    : replacement.versionedPath
            }
            guard invalidPaths.isEmpty else {
                throw SVNError.pathAliasRepairFailed(paths: invalidPaths)
            }
            for backup in backups {
                try? fileManager.removeItem(at: backup.directoryURL)
            }
            return refreshed
        } catch {
            var failedRestores: [BackupRecord] = []
            for backup in backups.reversed() {
                guard backup.aliasWasRemoved else {
                    try? fileManager.removeItem(at: backup.directoryURL)
                    continue
                }
                do {
                    if fileManager.fileExists(atPath: backup.versionedURL.path) {
                        try fileManager.removeItem(at: backup.versionedURL)
                    }
                    try fileManager.copyItem(at: backup.backupURL, to: backup.localURL)
                    guard try SVNFileSystem.filesHaveEqualContents(backup.backupURL, backup.localURL) else {
                        throw SVNError.pathAliasRepairFailed(paths: [backup.replacement.versionedPath])
                    }
                    try? fileManager.removeItem(at: backup.directoryURL)
                } catch {
                    failedRestores.append(backup)
                }
            }
            guard failedRestores.isEmpty else {
                throw SVNError.fileReplacementRecoveryFailed(
                    paths: failedRestores.map(\.replacement.versionedPath),
                    backupPaths: failedRestores.map(\.backupURL.path)
                )
            }
            throw error
        }
    }

    private static func selectedCanonicalFileReplacements(
        in snapshot: SVNWorkingCopySnapshot,
        selectedPaths: [String]
    ) -> [SVNCanonicalFileReplacement] {
        let modifiedPaths = Set(snapshot.statuses.compactMap { entry in
            entry.item == .modified ? entry.path.precomposedStringWithCanonicalMapping : nil
        })
        let selectedKeys = selectedPaths.map { $0.precomposedStringWithCanonicalMapping }
        return snapshot.canonicalFileReplacements.filter { replacement in
            let path = replacement.versionedPath.precomposedStringWithCanonicalMapping
            guard modifiedPaths.contains(path) else { return false }
            return selectedKeys.contains { selected in
                selected == "." || path == selected || path.hasPrefix(selected + "/")
            }
        }
    }

    static func additionRollbackRoots(
        _ additions: [String],
        versionedPathsByCanonicalKey: [String: [String]],
        preexistingScheduledAdditionPaths: [String] = []
    ) -> [String] {
        let preexistingKeys = Set(preexistingScheduledAdditionPaths.map(SVNPathIdentity.init(rawPath:)))
        let roots = additions.map { path -> String in
            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { return path }
            for length in 1...components.count {
                let prefix = components.prefix(length).joined(separator: "/")
                let identity = SVNPathIdentity(rawPath: prefix)
                if preexistingKeys.contains(identity) { continue }
                if versionedPathsByCanonicalKey[identity.canonicalKey] == nil { return prefix }
            }
            return path
        }
        return normalizedCommitPaths(roots)
    }

    /// SVN 경로 공간은 원문 UTF-8 바이트입니다. Swift String의 동등성은 NFC와 NFD를
    /// 같게 보므로, 정규화만 다른 두 경로를 여기서 접으면 한쪽이 조용히 커밋 목록에서
    /// 빠집니다. 중복 제거와 상위 경로 판정 모두 바이트 기준으로 합니다.
    static func normalizedCommitPaths(_ paths: [String]) -> [String] {
        let selectedPaths = Set(paths.map { SVNPathIdentity(rawPath: $0) })
        if selectedPaths.contains(SVNPathIdentity(rawPath: ".")) { return ["."] }

        return selectedPaths.filter { identity in
            let path = identity.rawPath
            var searchEnd = path.endIndex
            while let separator = path[..<searchEnd].lastIndex(of: "/") {
                if selectedPaths.contains(SVNPathIdentity(rawPath: String(path[..<separator]))) {
                    return false
                }
                searchEnd = separator
            }
            return true
        }
        .map(\.rawPath)
        .sorted()
    }

    private static func normalizedNewDestinationPath(_ path: String) -> String {
        guard let separator = path.lastIndex(of: "/") else {
            return path.precomposedStringWithCanonicalMapping
        }
        let componentStart = path.index(after: separator)
        let prefix = path[...separator]
        let component = path[componentStart...].precomposedStringWithCanonicalMapping
        return String(prefix) + component
    }

    private static func repositoryPathEscapingLiteralPercents(_ path: String) -> String {
        let hasLeadingSlash = path.hasPrefix("/")
        let escaped = pathComponents(path)
            .map { $0.replacingOccurrences(of: "%", with: "%25") }
            .joined(separator: "/")
        return hasLeadingSlash ? "/" + escaped : escaped
    }

    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func validatePropertyName(_ name: String) throws {
        guard !name.isEmpty,
              !name.hasPrefix("-"),
              !name.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw SVNClientArgumentError.unsupportedPropertyName(name)
        }
    }

    /// 로그 메시지를 임시 파일에 씁니다. NUL 검사와 atomic 쓰기가 한곳에만 있도록
    /// 로그 메시지를 쓰는 모든 명령이 이 함수를 통과합니다. 반환한 폴더는 호출부가
    /// `defer`로 지웁니다.
    private static func makeSVNLogMessageFile(_ message: String) throws -> (directory: URL, path: String) {
        guard !message.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw SVNClientArgumentError.unsupportedLogMessage
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-log-message-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("message", isDirectory: false)
        try Data(message.utf8).write(to: fileURL, options: .atomic)
        return (directory, fileURL.path)
    }

    private func withSVNLogMessageFile<Result>(
        _ message: String,
        operation: (String) async throws -> Result
    ) async throws -> Result {
        let messageFile = try Self.makeSVNLogMessageFile(message)
        defer { try? FileManager.default.removeItem(at: messageFile.directory) }
        return try await operation(messageFile.path)
    }

    // MARK: - 공통 명령 실행

    /// 단일 파일/폴더를 받는 SVN 명령의 공통 진입점입니다. 로컬 프로젝트
    /// 경로를 작업 복사본 루트 기준 저장소 경로로 바꾼 뒤, 원문 UTF-8 바이트를
    /// 보존하는 파일 운반 방식으로 실행합니다.
    private func checkedRunWithSingleWorkingCopyPathArgument(
        _ arguments: [String],
        projectRelativePath: String,
        at localProjectPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [],
        outputDestinationURL: URL? = nil
    ) async throws -> SVNCommandResult {
        let commandPath = try await resolveWorkingCopyCommandPath(
            localProjectPath: localProjectPath,
            projectRelativePath: projectRelativePath,
            credentials: credentials
        )
        return try await checkedRunWithSingleSVNPathArgument(
            arguments,
            svnPathArgument: commandPath.svnPathRelativeToWorkingCopyRoot,
            outputDestinationURL: outputDestinationURL,
            at: commandPath.workingCopyRootPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
    }

    private func checkedRunWithTwoSVNPathArguments(
        _ arguments: [String],
        firstSVNPathArgument: String,
        secondSVNPathArgument: String,
        escapeFirstPegSyntax: Bool = true,
        escapeSecondPegSyntax: Bool = true,
        at workingDirectoryPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> SVNCommandResult {
        try await checkedRunWithSVNPathArguments(
            arguments,
            svnPathArguments: [firstSVNPathArgument, secondSVNPathArgument],
            escapePegSyntax: [escapeFirstPegSyntax, escapeSecondPegSyntax],
            at: workingDirectoryPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
    }

    private func checkedRunWithSVNPathArguments(
        _ arguments: [String],
        svnPathArguments: [String],
        escapePegSyntax: [Bool],
        at workingDirectoryPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [],
        progress: SVNOutputHandler? = nil
    ) async throws -> SVNCommandResult {
        precondition(svnPathArguments.count == escapePegSyntax.count)
        let unsupportedSVNPaths = Self.svnPathsUnsafeForLineDelimitedTransport(svnPathArguments)
        guard unsupportedSVNPaths.isEmpty else {
            throw SVNError.unsupportedTargetPath(paths: unsupportedSVNPaths)
        }
        let escapedArguments = zip(svnPathArguments, escapePegSyntax).map { path, shouldEscape in
            shouldEscape ? Self.svnPathEscapingPegSyntax(path) : path
        }
        let result = try await run(
            arguments,
            svnPathArguments: escapedArguments,
            at: workingDirectoryPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: progress
        )
        guard result.exitCode == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SVNError.commandFailed(
                command: "svn \(arguments.first ?? "")",
                message: detail.isEmpty ? result.output : detail
            )
        }
        return result
    }

    /// 여러 작업 복사본 경로는 `--targets` 파일에 원문 UTF-8로 기록합니다.
    /// Foundation `Process.arguments`를 거치면 한글이 NFD로 변할 수 있으므로,
    /// 커밋·add·delete·revert 대상은 이 함수 밖에서 직접 인자로 만들지 않습니다.
    private func checkedRunWithMultipleWorkingCopyPathArguments(
        _ arguments: [String],
        projectRelativePaths: [String],
        at localProjectPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> SVNCommandResult {
        guard !projectRelativePaths.isEmpty else {
            throw SVNClientArgumentError.emptyTargets(command: arguments.first ?? "")
        }
        var workingCopyCommandPaths: [SVNWorkingCopyCommandPath] = []
        workingCopyCommandPaths.reserveCapacity(projectRelativePaths.count)
        for projectRelativePath in projectRelativePaths {
            let commandPath = try await resolveWorkingCopyCommandPath(
                localProjectPath: localProjectPath,
                projectRelativePath: projectRelativePath,
                credentials: credentials
            )
            workingCopyCommandPaths.append(commandPath)
        }
        let workingCopyRootPath = workingCopyCommandPaths.first?.workingCopyRootPath ?? localProjectPath
        let svnPathsRelativeToWorkingCopyRoot = workingCopyCommandPaths.map(
            \.svnPathRelativeToWorkingCopyRoot
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-targets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let svnTargetsFileURL = temporaryDirectory.appendingPathComponent("targets", isDirectory: false)
        try Self.svnTargetsFileContents(svnPathsRelativeToWorkingCopyRoot)
            .write(to: svnTargetsFileURL, options: .atomic)

        return try await checkedRun(
            arguments + ["--targets", svnTargetsFileURL.path],
            at: workingCopyRootPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
    }

    /// Foundation `Process.arguments`가 macOS 파일 경로를 NFD로 변환하는 경우에도
    /// SVN 관리 경로의 원문 UTF-8 바이트를 그대로 마지막 인자로 전달합니다.
    private func checkedRunWithSingleSVNPathArgument(
        _ arguments: [String],
        svnPathArgument: String,
        escapePegSyntax: Bool = true,
        outputDestinationURL: URL? = nil,
        at workingDirectoryPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = []
    ) async throws -> SVNCommandResult {
        let unsupportedSVNPaths = Self.svnPathsUnsafeForLineDelimitedTransport([svnPathArgument])
        guard unsupportedSVNPaths.isEmpty else {
            throw SVNError.unsupportedTargetPath(paths: unsupportedSVNPaths)
        }
        let result = try await run(
            arguments,
            svnPathArgument: escapePegSyntax
                ? Self.svnPathEscapingPegSyntax(svnPathArgument)
                : svnPathArgument,
            outputDestinationURL: outputDestinationURL,
            at: workingDirectoryPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures
        )
        guard result.exitCode == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SVNError.commandFailed(
                command: "svn \(arguments.first ?? "")",
                message: detail.isEmpty ? result.output : detail
            )
        }
        return result
    }

    static func svnPathEscapingPegSyntax(_ path: String) -> String {
        let finalComponent = path.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        let containsEncodedAtSign = finalComponent.range(
            of: "%40",
            options: .caseInsensitive
        ) != nil
        return finalComponent.contains("@") || containsEncodedAtSign ? path + "@" : path
    }

    static func svnTargetsFileContents(_ svnPaths: [String]) throws -> Data {
        guard !svnPaths.isEmpty else {
            throw SVNClientArgumentError.emptyTargets(command: "targets")
        }
        let unsupportedSVNPaths = svnPathsUnsafeForLineDelimitedTransport(svnPaths)
        guard unsupportedSVNPaths.isEmpty else {
            throw SVNError.unsupportedTargetPath(paths: unsupportedSVNPaths)
        }
        return Data((svnPaths.map(svnPathEscapingPegSyntax).joined(separator: "\n") + "\n").utf8)
    }

    private static func svnPathsUnsafeForLineDelimitedTransport(_ svnPaths: [String]) -> [String] {
        svnPaths.filter { path in
            path.isEmpty || path.unicodeScalars.contains {
                $0.value == 0 || $0.value == 10 || $0.value == 13
            }
        }
    }

    private func ignorePatterns(
        at path: String,
        directory: String,
        propertyKind: SVNIgnorePropertyKind,
        credentials: SVNCredentials?
    ) async throws -> [String] {
        let result = try await runWithSingleWorkingCopyPathArgument(
            ["propget", propertyKind.propertyName, "--strict"],
            projectRelativePath: directory,
            at: path,
            credentials: credentials
        )
        if result.exitCode != 0, result.error.contains("W200017") { return [] }
        guard result.exitCode == 0 else {
            throw SVNError.commandFailed(command: "svn propget \(propertyKind.propertyName)", message: result.error)
        }
        return result.output.split(whereSeparator: \.isNewline).map(String.init)
    }

    /// `svn propget`처럼 특정 종료 코드를 호출자가 직접 해석해야 하는 경우에도
    /// 경로 원문 보존 규칙은 동일해야 하므로, 검사 없는 실행도 별도 경로 함수로
    /// 제공합니다. 일반 기능에서는 종료 코드를 검사하는 checked 버전을 사용합니다.
    private func runWithSingleWorkingCopyPathArgument(
        _ arguments: [String],
        projectRelativePath: String,
        at localProjectPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> SVNCommandResult {
        let commandPath = try await resolveWorkingCopyCommandPath(
            localProjectPath: localProjectPath,
            projectRelativePath: projectRelativePath,
            credentials: credentials
        )
        let unsupportedSVNPaths = Self.svnPathsUnsafeForLineDelimitedTransport([
            commandPath.svnPathRelativeToWorkingCopyRoot
        ])
        guard unsupportedSVNPaths.isEmpty else {
            throw SVNError.unsupportedTargetPath(paths: unsupportedSVNPaths)
        }
        return try await run(
            arguments,
            svnPathArgument: Self.svnPathEscapingPegSyntax(
                commandPath.svnPathRelativeToWorkingCopyRoot
            ),
            at: commandPath.workingCopyRootPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
    }

    @discardableResult
    private func checkedRun(
        _ arguments: [String],
        at workingDirectoryPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [],
        progress: SVNOutputHandler? = nil
    ) async throws -> SVNCommandResult {
        let result = try await run(
            arguments,
            at: workingDirectoryPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate,
            allowedServerCertificateFailures: allowedServerCertificateFailures,
            progress: progress
        )
        guard result.exitCode == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? result.output : detail
            if arguments.first == "commit", Self.isWorkingCopyOutOfDateError(message) {
                throw SVNError.workingCopyOutOfDate(details: message)
            }
            throw SVNError.commandFailed(command: "svn \(arguments.first ?? "")", message: message)
        }
        return result
    }

    /// `svn status --show-updates`는 삭제 예약된 디렉터리의 하위 서버 변경을
    /// 표시하지 않을 수 있습니다. 커밋 서버가 반환한 표준 오류 코드를 최종
    /// 판정으로 사용해 일반 명령 실패와 업데이트 필요 상태를 구분합니다.
    private static func isWorkingCopyOutOfDateError(_ message: String) -> Bool {
        let hasOutOfDateCode = message.contains("E155011") || message.contains("E170004")
        return hasOutOfDateCode && message.localizedCaseInsensitiveContains("out of date")
    }

    public static func needsCleanup(_ message: String) -> Bool {
        message.contains("E155004") || message.contains("E155037")
    }

    public static func needsCleanup(_ error: Error) -> Bool {
        guard case let SVNError.commandFailed(_, message) = error else { return false }
        return needsCleanup(message)
    }

    public static func isAuthenticationError(_ message: String) -> Bool {
        message.contains("E170001") || message.contains("E215004")
    }

    public static func isAuthenticationError(_ error: Error) -> Bool {
        commandFailureMessage(from: error).map(isAuthenticationError) ?? false
    }

    public static func isLockConflictError(_ message: String) -> Bool {
        message.contains("E195022") || message.contains("E160037")
    }

    public static func isLockConflictError(_ error: Error) -> Bool {
        commandFailureMessage(from: error).map(isLockConflictError) ?? false
    }

    public static func isServerCertificateValidationError(_ message: String) -> Bool {
        message.contains("E175002") || message.contains("E230001")
    }

    public static func isServerCertificateValidationError(_ error: Error) -> Bool {
        commandFailureMessage(from: error).map(isServerCertificateValidationError) ?? false
    }

    public static func isRepositoryConnectionError(_ message: String) -> Bool {
        message.contains("E170013") || message.contains("E180001")
    }

    public static func isRepositoryConnectionError(_ error: Error) -> Bool {
        commandFailureMessage(from: error).map(isRepositoryConnectionError) ?? false
    }

    public static func isWorkingCopyFormatTooOldError(_ message: String) -> Bool {
        message.contains("E155036")
    }

    public static func isWorkingCopyFormatTooOldError(_ error: Error) -> Bool {
        commandFailureMessage(from: error).map(isWorkingCopyFormatTooOldError) ?? false
    }

    private static func commandFailureMessage(from error: Error) -> String? {
        guard case let SVNError.commandFailed(_, message) = error else { return nil }
        return message
    }

    private func run(
        _ arguments: [String],
        svnPathArgument: String? = nil,
        svnPathArguments: [String]? = nil,
        outputDestinationURL: URL? = nil,
        at workingDirectoryPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false,
        allowedServerCertificateFailures: Set<SVNServerCertificateFailure> = [],
        progress: SVNOutputHandler? = nil
    ) async throws -> SVNCommandResult {
        let process = Process()
        let svnExecutable = try svnExecutableURL()
        // Finder/Dock에서 실행한 GUI 앱은 LANG/LC_ALL이 없을 수 있습니다.
        // SVN은 명령행 인자를 현재 로케일에서 UTF-8로 변환하므로, 로케일이
        // 비어 있으면 한글 커밋 메시지가 mojibake 상태로 저장될 수 있습니다.
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment
        let configDirectory = try svnConfigDirectory()
        var globalArguments = ["--non-interactive", "--config-dir", configDirectory.path]
        var certificateFailures = allowedServerCertificateFailures
        if allowUntrustedServerCertificate {
            certificateFailures.formUnion([.unknownCertificateAuthority, .commonNameMismatch])
        }
        if !certificateFailures.isEmpty {
            let values = SVNServerCertificateFailure.allCases
                .filter(certificateFailures.contains)
                .map(\.rawValue)
                .joined(separator: ",")
            globalArguments.append("--trust-server-cert-failures=\(values)")
        }
        var password: String?
        var rawUsername: String?
        if let credentials, !credentials.username.isEmpty {
            guard !credentials.username.unicodeScalars.contains(where: {
                $0.value == 0 || $0.value == 10 || $0.value == 13
            }) else {
                throw SVNClientArgumentError.unsupportedUsername
            }
            if credentials.username.allSatisfy(\.isASCII) {
                globalArguments += ["--username", credentials.username]
            } else {
                // 사용자명도 경로와 같은 이유로 원문 UTF-8 파일 운반이 필요합니다.
                rawUsername = credentials.username
            }
            if let storedPassword = credentials.password, !storedPassword.isEmpty {
                globalArguments += ["--password-from-stdin", "--no-auth-cache"]
                password = storedPassword
            }
        }

        // `Process.arguments`에 한글 값을 직접 넣으면 Foundation이 NFD로 바꿀 수 있습니다.
        // 원문 UTF-8을 파일에 쓰고 POSIX shell이 읽어 argv로 넘기면 그 변환을 피할 수 있습니다.
        if let svnPathArguments { precondition(!svnPathArguments.isEmpty) }
        let rawPathArguments = svnPathArguments ?? svnPathArgument.map { [$0] } ?? []
        var rawTransportDirectory: URL?
        defer {
            if let rawTransportDirectory {
                try? FileManager.default.removeItem(at: rawTransportDirectory)
            }
        }

        if rawUsername == nil, rawPathArguments.isEmpty {
            process.executableURL = svnExecutable
            process.arguments = globalArguments + arguments
        } else {
            let transportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("svn-mac-raw-arguments-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: transportDirectory, withIntermediateDirectories: true)
            rawTransportDirectory = transportDirectory

            let rawValues = (rawUsername.map { [(name: "username", value: $0)] } ?? [])
                + rawPathArguments.enumerated().map { (name: "argument_\($0.offset + 1)", value: $0.element) }
            let valueURLs = try rawValues.enumerated().map { index, rawValue in
                let valueURL = transportDirectory.appendingPathComponent("value-\(index + 1)")
                try (Data(rawValue.value.utf8) + Data([0x0A])).write(to: valueURL)
                return valueURL
            }
            let fileAssignments = rawValues.indices.map { "\(rawValues[$0].name)_file=$\($0 + 1)" }
            let svnExecutableIndex = rawValues.count + 1
            let valueReads = rawValues.indices.map {
                "IFS= read -r \(rawValues[$0].name) < \"$\(rawValues[$0].name)_file\""
            }
            let usernameOption = rawUsername == nil ? "" : "--username \"$username\" "
            let pathReferences = rawPathArguments.indices
                .map { "\"$argument_\($0 + 1)\"" }
                .joined(separator: " ")
            let pathSuffix = rawPathArguments.isEmpty ? "" : " -- \(pathReferences)"
            let shellCommand = (
                fileAssignments
                + ["svn_executable=$\(svnExecutableIndex)", "shift \(svnExecutableIndex)"]
                + valueReads
                + ["exec \"$svn_executable\" \(usernameOption)\"$@\"\(pathSuffix)"]
            ).joined(separator: "; ")

            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c",
                shellCommand,
                "svn-mac-raw-arguments",
            ] + valueURLs.map(\.path) + [svnExecutable.path] + globalArguments + arguments
        }
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath)

        // stdout/stderr를 Pipe로 계속 읽지 않으면 출력이 큰 명령에서 버퍼가 차
        // 프로세스가 멈출 수 있습니다. 임시 파일로 받으면 waitUntilExit 중에도
        // 출력 크기와 관계없이 안전하게 명령 완료를 기다릴 수 있습니다.
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let outputURL = outputDestinationURL
            ?? temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        let outputProgressReader = try progress.map {
            try SVNOutputProgressReader(url: outputURL, progress: $0)
        }
        let errorProgressReader = try progress.map {
            try SVNOutputProgressReader(url: errorURL, progress: $0)
        }
        // 비밀번호는 프로세스 인자에 넣지 않습니다. 명령행은 다른 프로세스에서
        // 조회될 수 있으므로 SVN의 --password-from-stdin 계약만 사용합니다.
        let input = password.map { _ in Pipe() }
        if let input {
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }
        process.standardInput = input

        let processController = SVNRunningProcess(process: process)
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completion = SVNProcessCompletion(continuation)
                let progressQueue = DispatchQueue(
                    label: "com.mrdevello.svnmac.svn-progress-\(UUID().uuidString)"
                )
                let progressTimer = progress.map { _ in
                    let timer = DispatchSource.makeTimerSource(queue: progressQueue)
                    timer.schedule(deadline: .now(), repeating: .milliseconds(50))
                    timer.setEventHandler {
                        do {
                            try outputProgressReader?.drain()
                            try errorProgressReader?.drain()
                        } catch {
                            processController.record(error)
                            processController.terminate()
                        }
                    }
                    return timer
                }
                process.terminationHandler = { _ in
                    progressQueue.async {
                        progressTimer?.cancel()
                        try? outputHandle.close()
                        try? errorHandle.close()
                        do {
                            try outputProgressReader?.drain(isFinal: true)
                            try errorProgressReader?.drain(isFinal: true)
                            if processController.wasCancelled {
                                completion.resume(throwing: CancellationError())
                            } else if let error = processController.recordedError {
                                completion.resume(throwing: error)
                            } else {
                                completion.resume()
                            }
                        } catch {
                            completion.resume(throwing: error)
                        }
                    }
                }

                do {
                    progressTimer?.resume()
                    try process.run()
                    if let password, let input {
                        // 프로세스가 인증 입력 전에 종료하면 EPIPE가 발생할 수 있습니다.
                        // `isRunning`은 종료 핸들러와 경합하므로 쓰기 오류 자체를 실행
                        // 오류로 승격하지 않고, 아래의 종료 코드와 stderr로 판정합니다.
                        try? input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
                        try? input.fileHandleForWriting.close()
                    }
                } catch {
                    progressTimer?.cancel()
                    try? outputHandle.close()
                    try? errorHandle.close()
                    completion.resume(throwing: error)
                }
            }
        } onCancel: {
            processController.cancel()
        }

        let output = outputDestinationURL == nil
            ? String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)
            : ""
        let error = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
        return SVNCommandResult(
            output: output,
            error: error,
            exitCode: process.terminationStatus
        )
    }

    private func svnExecutableURL() throws -> URL {
        // 테스트 주입 경로, 환경 변수, 앱 번들, 개발 Mac 설치 경로 순서로 찾습니다.
        // 배포 앱에서는 Contents/Helpers/svn이 가장 먼저 사용됩니다.
        var candidates: [String] = []
        if let executablePath { candidates.append(executablePath) }
        if let override = ProcessInfo.processInfo.environment["SVN_EXECUTABLE"], !override.isEmpty {
            candidates.append(override)
        }
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("svn", isDirectory: false)
            .path
        if FileManager.default.isExecutableFile(atPath: helper) {
            candidates.append(helper)
        }
        if let bundled = Bundle.main.url(forResource: "svn", withExtension: nil, subdirectory: "bin")?.path {
            candidates.append(bundled)
        }
        candidates += [
            "/opt/homebrew/bin/svn",
            "/usr/local/bin/svn",
            "/usr/bin/svn",
        ]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw SVNError.svnExecutableNotFound
        }
        return URL(fileURLWithPath: path)
    }

    private func svnConfigDirectory() throws -> URL {
        // 시스템 SVN 설정과 앱 설정이 서로 영향을 주지 않도록 앱 전용 config-dir을
        // 사용합니다. 테스트에서는 임시 디렉터리를 주입할 수 있습니다.
        if let configDirectoryPath {
            let directory = URL(fileURLWithPath: configDirectoryPath, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        let directory = try SVNApplicationSupport.rootDirectory()
            .appendingPathComponent("Subversion", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class SVNRunningProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancellationRequested = false
    private var error: Error?

    init(process: Process) {
        self.process = process
    }

    var wasCancelled: Bool {
        lock.withLock { cancellationRequested }
    }

    var recordedError: Error? {
        lock.withLock { error }
    }

    func record(_ error: Error) {
        lock.withLock {
            if self.error == nil { self.error = error }
        }
    }

    func cancel() {
        lock.withLock { cancellationRequested = true }
        terminate()
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

private final class SVNProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        takeContinuation()?.resume()
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Void, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

private final class SVNOutputProgressReader: @unchecked Sendable {
    private static let readSize = 64 * 1024

    private let handle: FileHandle
    private let progress: SVNOutputHandler
    private var pending = Data()

    init(url: URL, progress: @escaping SVNOutputHandler) throws {
        handle = try FileHandle(forReadingFrom: url)
        self.progress = progress
    }

    deinit {
        try? handle.close()
    }

    func drain(isFinal: Bool = false) throws {
        while let data = try handle.read(upToCount: Self.readSize), !data.isEmpty {
            pending.append(data)
        }

        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending.prefix(through: newline)
            progress(String(decoding: line, as: UTF8.self))
            pending.removeSubrange(...newline)
        }

        if isFinal, !pending.isEmpty {
            progress(String(decoding: pending, as: UTF8.self))
            pending.removeAll(keepingCapacity: false)
        }
    }
}
