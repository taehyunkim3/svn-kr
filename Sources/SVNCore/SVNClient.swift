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

    public func status(at path: String, credentials: SVNCredentials? = nil) async throws -> [SVNStatusEntry] {
        let result = try checkedRun(["status", "--xml"], at: path, credentials: credentials)
        return try SVNXMLParser.statuses(from: Data(result.output.utf8))
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
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        try checkedRun(
            ["diff", "--change", revision],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    public func workingCopyRevision(at path: String, credentials: SVNCredentials? = nil) async throws -> String {
        try checkedRun(["info", "--show-item", "revision"], at: path, credentials: credentials)
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    public func commit(
        at path: String,
        paths: [String],
        message: String,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> String {
        // 선택 커밋 전에 SVN 관리 대상이 아닌 파일과 디스크에서 사라진 파일을
        // 각각 add/delete 예약해 사용자가 별도 명령을 실행하지 않아도 되게 합니다.
        let currentStatuses = try await status(at: path, credentials: credentials)
        for item in paths {
            let status = currentStatuses.first(where: { $0.path == item })
            if status?.item == .unversioned {
                _ = try checkedRun(["add", "--parents", "--", item], at: path, credentials: credentials)
            } else if status?.item == .missing {
                _ = try checkedRun(["delete", "--force", "--", item], at: path, credentials: credentials)
            }
        }
        return try checkedRun(
            ["commit", "--message", message, "--"] + paths,
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        ).output
    }

    // MARK: - 공통 명령 실행

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
