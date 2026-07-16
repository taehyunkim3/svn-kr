import Foundation

public actor SVNClient {
    private let executablePath: String?
    private let configDirectoryPath: String?

    public init(executablePath: String? = nil, configDirectoryPath: String? = nil) {
        self.executablePath = executablePath
        self.configDirectoryPath = configDirectoryPath
    }

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

    public func log(
        at path: String,
        limit: Int = 50,
        credentials: SVNCredentials? = nil,
        allowUntrustedServerCertificate: Bool = false
    ) async throws -> [SVNLogEntry] {
        let result = try checkedRun(
            ["log", "--xml", "--verbose", "--with-all-revprops", "--revision", "HEAD:1", "--limit", String(limit)],
            at: path,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        return try SVNXMLParser.logs(from: Data(result.output.utf8))
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
        let currentStatuses = try await status(at: path, credentials: credentials)
        for item in paths {
            let status = currentStatuses.first(where: { $0.path == item })
            if status?.item == "unversioned" {
                _ = try checkedRun(["add", "--parents", "--", item], at: path, credentials: credentials)
            } else if status?.item == "missing" {
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
