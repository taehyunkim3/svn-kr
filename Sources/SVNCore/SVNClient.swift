import Foundation

/// SVN CLI 호출을 직렬화하는 코어 서비스입니다.
///
/// actor로 선언해 동일 클라이언트에서 update와 commit 같은 명령이 동시에
/// 작업 복사본을 변경하지 않도록 보장합니다. 실제 CLI 실행은 `run` 한곳을
/// 통과하므로 인증 인자와 출력 수집 방식도 모든 명령에서 동일합니다.
public actor SVNClient {
    private let executablePath: String?
    private let configDirectoryPath: String?

    public init(executablePath: String? = nil, configDirectoryPath: String? = nil) {
        self.executablePath = executablePath
        self.configDirectoryPath = configDirectoryPath
    }

    // MARK: - 사용자가 실행하는 SVN 기능

    public func checkout(
        repositoryURL: String,
        destinationPath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        let normalizedRepositoryURL = repositoryURL.precomposedStringWithCanonicalMapping
        let repositoryURL = URL(string: normalizedRepositoryURL)?.absoluteString ?? normalizedRepositoryURL
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return try checkedRun(
            ["checkout", repositoryURL, "."],
            at: destination.path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    public func validateWorkingCopy(at path: String, credentials: SVNCredentials? = nil) async throws {
        let result = try run(["info", "--show-item", "wc-root"], at: path, credentials: credentials)
        guard result.exitCode == 0 else { throw SVNError.invalidWorkingCopy }
    }

    public func workingCopyRepositoryURL(at path: String, credentials: SVNCredentials? = nil) async throws -> String {
        try checkedRun(["info", "--show-item", "url"], at: path, credentials: credentials)
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
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
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> SVNRecoveryResult {
        let source = URL(fileURLWithPath: sourcePath, isDirectory: true).standardizedFileURL
        let destination = URL(fileURLWithPath: destinationPath, isDirectory: true).standardizedFileURL
        try SVNWorkingCopyRecovery.requireEmptyDestination(destination)

        let preview = try await recoveryPreview(at: source.path, credentials: credentials)
        guard preview.blockingPaths.isEmpty else {
            throw SVNError.recoveryBlocked(paths: preview.blockingPaths)
        }
        let repositoryURL = try await workingCopyRepositoryURL(at: source.path, credentials: credentials)
        _ = try await checkout(
            repositoryURL: repositoryURL,
            destinationPath: destination.path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
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
    }

    public func status(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNStatusEntry] {
        let result = try checkedRun(["status", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.statuses(from: Data(result.output.utf8))
    }

    public func workingCopyEntries(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNWorkingCopyEntry] {
        let result = try checkedRun(["status", "--verbose", "--no-ignore", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.workingCopyEntries(from: Data(result.output.utf8))
    }

    public func workingCopySnapshot(at path: String, credentials: SVNCredentials? = nil) async throws -> SVNWorkingCopySnapshot {
        let result = try checkedRun(["status", "--verbose", "--no-ignore", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.workingCopySnapshot(from: Data(result.output.utf8))
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
        let targets = before.repairableAliasPaths
        if !targets.isEmpty {
            _ = try checkedRunWithTargets(
                ["revert", "--depth", "infinity"],
                targets: targets,
                at: path,
                credentials: credentials
            )
        }
        let after = try await workingCopySnapshot(at: path, credentials: credentials)
        guard after.repairableAliasPaths.isEmpty else {
            throw SVNError.pathAliasRepairFailed(paths: after.collisions.map(\.displayPath))
        }
        return after
    }

    public func ignoredStatus(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNStatusEntry] {
        let result = try checkedRun(["status", "--no-ignore", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.statuses(from: Data(result.output.utf8)).filter { $0.item == .ignored }
    }

    public func ignoreRules(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNIgnoreRule] {
        let result = try run(["propget", "svn:ignore", "--recursive", "--xml", "."], at: path, credentials: credentials)
        if result.exitCode != 0, result.error.contains("W200017") { return [] }
        guard result.exitCode == 0 else {
            throw SVNError.commandFailed(command: "svn propget", message: result.error)
        }
        return try SVNXMLParser.ignoreRules(from: Data(result.output.utf8))
    }

    public func addIgnoreRule(
        at path: String,
        directory: String,
        pattern: String,
        credentials: SVNCredentials? = nil
    ) async throws {
        let existing = try ignorePatterns(at: path, directory: directory, credentials: credentials)
        guard !existing.contains(pattern) else { return }
        let value = (existing + [pattern]).joined(separator: "\n") + "\n"
        _ = try checkedRun(["propset", "svn:ignore", value, "--", directory], at: path, credentials: credentials)
    }

    public func removeIgnoreRule(
        at path: String,
        directory: String,
        pattern: String,
        credentials: SVNCredentials? = nil
    ) async throws {
        let remaining = try ignorePatterns(at: path, directory: directory, credentials: credentials)
            .filter { $0 != pattern }
        if remaining.isEmpty {
            _ = try checkedRun(["propdel", "svn:ignore", "--", directory], at: path, credentials: credentials)
        } else {
            let value = remaining.joined(separator: "\n") + "\n"
            _ = try checkedRun(["propset", "svn:ignore", value, "--", directory], at: path, credentials: credentials)
        }
    }

    public func repositoryLocks(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> [SVNLockInfo] {
        let result = try checkedRun(
            ["status", "--show-updates", "--xml"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        return try SVNXMLParser.repositoryLocks(fromStatus: Data(result.output.utf8))
    }

    public func lockInfo(
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> SVNLockInfo? {
        let result = try checkedRun(
            ["info", "--xml", "--revision", "HEAD", "--", relativePath],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        return try SVNXMLParser.repositoryLock(fromInfo: Data(result.output.utf8))
    }

    public func lock(
        at path: String,
        relativePath: String,
        comment: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        try checkedRun(
            ["lock", "--message", comment, "--", relativePath],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    public func unlock(
        at path: String,
        relativePath: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        try checkedRun(
            ["unlock", "--", relativePath],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    public func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials? = nil) async throws -> SVNConflictDetails? {
        let result = try checkedRun(["info", "--xml", "--", relativePath], at: path, credentials: credentials)
        return try SVNXMLParser.conflictDetails(fromInfo: Data(result.output.utf8))
    }

    public func resolveConflict(
        at path: String,
        relativePath: String,
        choice: SVNConflictChoice,
        credentials: SVNCredentials? = nil
    ) async throws -> String {
        try checkedRun(["resolve", "--accept", choice.rawValue, "--", relativePath], at: path, credentials: credentials).output
    }

    public func log(
        at path: String,
        limit: Int = 50,
        endingAtRevision: String? = nil,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> [SVNLogEntry] {
        let revisionRange = "\(endingAtRevision ?? "HEAD"):1"
        let result = try checkedRun(
            ["log", "--xml", "--verbose", "--with-all-revprops", "--revision", revisionRange, "--limit", String(limit)],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
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
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        let targetPath = revisionTargetPath(
            repositoryPath: repositoryPath,
            workingCopyRepositoryPath: workingCopyRepositoryPath
        )
        let target = "^\(targetPath)@\(pegRevision)"
        return try checkedRun(
            ["diff", "--change", revision, "--", target],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    /// 로그 경로의 작업 복사본 root만 `svn info relative-url`이 반환한 실제
    /// 서버 경로로 교체합니다. root 아래의 이름은 원문을 보존해야 저장소에
    /// NFD 이름으로 남아 있는 과거 파일도 해당 리비전에서 조회할 수 있습니다.
    private func revisionTargetPath(repositoryPath: String, workingCopyRepositoryPath: String?) -> String {
        let repositoryPath = repositoryPath.hasPrefix("/") ? repositoryPath : "/\(repositoryPath)"
        guard let workingCopyRepositoryPath, !workingCopyRepositoryPath.isEmpty else {
            return repositoryPath
        }

        let rootPath = workingCopyRepositoryPath.hasPrefix("/")
            ? workingCopyRepositoryPath
            : "/\(workingCopyRepositoryPath)"
        let decodedRootPath = rootPath.removingPercentEncoding ?? rootPath
        let repositoryComponents = pathComponents(repositoryPath)
        let rootComponents = pathComponents(decodedRootPath)
        guard repositoryComponents.starts(with: rootComponents) else { return repositoryPath }

        let suffix = repositoryComponents.dropFirst(rootComponents.count).joined(separator: "/")
        let encodedRoot = rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = [encodedRoot, suffix].filter { !$0.isEmpty }
        return "/" + components.joined(separator: "/")
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public func workingCopyRevision(at path: String, credentials: SVNCredentials? = nil) async throws -> SVNWorkingCopyRevision {
        let result = try checkedRun(["status", "--verbose", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.workingCopyRevision(from: Data(result.output.utf8))
    }

    /// 작업 복사본 루트가 저장소 루트 아래에서 차지하는 경로를 반환합니다.
    /// `svn log --verbose`의 변경 경로는 저장소 루트 기준 절대 경로이므로,
    /// 화면에서 로컬 프로젝트 루트 기준 경로로 줄여 표시할 때 이 값이 필요합니다.
    public func workingCopyRepositoryPath(at path: String, credentials: SVNCredentials? = nil) async throws -> String {
        let relativeURL = try checkedRun(
            ["info", "--show-item", "relative-url"],
            at: path,
            credentials: credentials
        )
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard relativeURL.hasPrefix("^/") else { return relativeURL }
        return "/" + relativeURL.dropFirst(2)
    }

    public func workingCopyIsOutOfDate(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> Bool {
        let result = try checkedRun(
            ["status", "--show-updates", "--xml"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        return try SVNXMLParser.workingCopyIsOutOfDate(from: Data(result.output.utf8))
    }

    public func remoteChanges(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> [SVNStatusEntry] {
        let result = try checkedRun(
            ["status", "--show-updates", "--xml"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        return try SVNXMLParser.remoteChanges(from: Data(result.output.utf8))
    }

    public func update(
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        try checkedRun(
            ["update"],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    public func diff(at path: String, relativePath: String? = nil, credentials: SVNCredentials? = nil) async throws -> String {
        var arguments = ["diff"]
        if let relativePath { arguments.append(relativePath) }
        return try checkedRun(arguments, at: path, credentials: credentials).output
    }

    public func revert(at path: String, relativePath: String, credentials: SVNCredentials? = nil) async throws -> String {
        try checkedRun(["revert", "--", relativePath], at: path, credentials: credentials).output
    }

    public func fileLog(
        at path: String,
        relativePath: String,
        limit: Int = 100,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> [SVNLogEntry] {
        let result = try checkedRun(
            ["log", "--xml", "--verbose", "--with-all-revprops", "--limit", String(limit), "--", relativePath],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        return try SVNXMLParser.logs(from: Data(result.output.utf8))
    }

    public func commit(
        at path: String,
        paths: [String],
        message: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
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

        let resolvedPaths = try paths.map { selectedPath -> String in
            guard let resolved = snapshot.resolvedPath(for: selectedPath) else {
                throw SVNError.pathNormalizationCollision(
                    paths: [selectedPath.precomposedStringWithCanonicalMapping]
                )
            }
            return resolved
        }
        let currentStatuses = snapshot.statuses
        var statusByPath: [String: SVNStatusKind] = [:]
        for status in currentStatuses {
            statusByPath[status.path.precomposedStringWithCanonicalMapping] = status.item
        }

        let normalizedPaths = Self.normalizedCommitPaths(resolvedPaths)
        let additions = Self.normalizedCommitPaths(resolvedPaths.filter {
            statusByPath[$0.precomposedStringWithCanonicalMapping] == .unversioned
        })
        let deletions = Self.normalizedCommitPaths(resolvedPaths.filter {
            statusByPath[$0.precomposedStringWithCanonicalMapping] == .missing
        })

        var scheduledByThisCommit: [String] = []
        do {
            if !additions.isEmpty {
                scheduledByThisCommit.append(contentsOf: Self.additionRollbackRoots(
                    additions,
                    versionedPathsByCanonicalKey: snapshot.versionedPathsByCanonicalKey
                ))
                _ = try checkedRunWithTargets(
                    ["add", "--parents"],
                    targets: additions,
                    at: path,
                    credentials: credentials
                )
            }
            if !deletions.isEmpty {
                scheduledByThisCommit.append(contentsOf: deletions)
                _ = try checkedRunWithTargets(
                    ["delete", "--force"],
                    targets: deletions,
                    at: path,
                    credentials: credentials
                )
            }

            return try checkedRunWithTargets(
                ["commit", "--message", message],
                targets: normalizedPaths,
                at: path,
                credentials: credentials,
                allowUntrustedServerCertificate: allowUntrustedServerCertificate
            ).output
        } catch {
            let rollbackTargets = Self.normalizedCommitPaths(scheduledByThisCommit)
            if !rollbackTargets.isEmpty {
                _ = try? checkedRunWithTargets(
                    ["revert", "--depth", "infinity"],
                    targets: rollbackTargets,
                    at: path,
                    credentials: credentials
                )
            }
            throw error
        }
    }

    static func additionRollbackRoots(
        _ additions: [String],
        versionedPathsByCanonicalKey: [String: [String]]
    ) -> [String] {
        let roots = additions.map { path -> String in
            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { return path }
            for length in 1...components.count {
                let prefix = components.prefix(length).joined(separator: "/")
                let key = prefix.precomposedStringWithCanonicalMapping
                if versionedPathsByCanonicalKey[key] == nil { return prefix }
            }
            return path
        }
        return normalizedCommitPaths(roots)
    }

    static func normalizedCommitPaths(_ paths: [String]) -> [String] {
        let selectedPaths = Set(paths)
        if selectedPaths.contains(".") { return ["."] }

        return selectedPaths.filter { path in
            var searchEnd = path.endIndex
            while let separator = path[..<searchEnd].lastIndex(of: "/") {
                if selectedPaths.contains(String(path[..<separator])) {
                    return false
                }
                searchEnd = separator
            }
            return true
        }
        .sorted()
    }

    // MARK: - 공통 명령 실행

    private func checkedRunWithTargets(
        _ arguments: [String],
        targets: [String],
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) throws -> SVNCommandResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-targets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let targetsURL = temporaryDirectory.appendingPathComponent("targets", isDirectory: false)
        let contents = targets.joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: targetsURL, options: .atomic)

        return try checkedRun(
            arguments + ["--targets", targetsURL.path],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
    }

    private func ignorePatterns(at path: String, directory: String, credentials: SVNCredentials?) throws -> [String] {
        let result = try run(["propget", "svn:ignore", "--strict", "--", directory], at: path, credentials: credentials)
        if result.exitCode != 0, result.error.contains("W200017") { return [] }
        guard result.exitCode == 0 else {
            throw SVNError.commandFailed(command: "svn propget", message: result.error)
        }
        return result.output.split(whereSeparator: \.isNewline).map(String.init)
    }

    @discardableResult
    private func checkedRun(
        _ arguments: [String],
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) throws -> SVNCommandResult {
        let result = try run(
            arguments,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        guard result.exitCode == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SVNError.commandFailed(command: "svn \(arguments.first ?? "")", message: detail.isEmpty ? result.output : detail)
        }
        return result
    }

    private func run(
        _ arguments: [String],
        at path: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) throws -> SVNCommandResult {
        let process = Process()
        process.executableURL = try svnExecutableURL()
        // Finder/Dock에서 실행한 GUI 앱은 LANG/LC_ALL이 없을 수 있습니다.
        // SVN은 명령행 인자를 현재 로케일에서 UTF-8로 변환하므로, 로케일이
        // 비어 있으면 한글 커밋 메시지가 mojibake 상태로 저장될 수 있습니다.
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment
        let configDirectory = try svnConfigDirectory()
        var globalArguments = ["--non-interactive", "--config-dir", configDirectory.path]
        if allowUntrustedServerCertificate {
            globalArguments.append("--trust-server-cert-failures=unknown-ca,cn-mismatch")
        }
        var password: String?
        if let credentials, !credentials.username.isEmpty {
            globalArguments += ["--username", credentials.username]
            if let storedPassword = credentials.password, !storedPassword.isEmpty {
                globalArguments += ["--password-from-stdin", "--no-auth-cache"]
                password = storedPassword
            }
        }
        process.arguments = globalArguments + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        // stdout/stderr를 Pipe로 계속 읽지 않으면 출력이 큰 명령에서 버퍼가 차
        // 프로세스가 멈출 수 있습니다. 임시 파일로 받으면 waitUntilExit 중에도
        // 출력 크기와 관계없이 안전하게 명령 완료를 기다릴 수 있습니다.
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-mac-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let outputURL = temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        // 비밀번호는 프로세스 인자에 넣지 않습니다. 명령행은 다른 프로세스에서
        // 조회될 수 있으므로 SVN의 --password-from-stdin 계약만 사용합니다.
        let input = password.map { _ in Pipe() }
        process.standardInput = input

        do {
            try process.run()
            if let password, let input {
                input.fileHandleForWriting.write(Data((password + "\n").utf8))
                try input.fileHandleForWriting.close()
            }
            process.waitUntilExit()
            try outputHandle.close()
            try errorHandle.close()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            throw error
        }

        let output = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)
        let error = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
        return SVNCommandResult(output: output, error: error, exitCode: process.terminationStatus)
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
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("SVN Mac", isDirectory: true)
            .appendingPathComponent("Subversion", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
