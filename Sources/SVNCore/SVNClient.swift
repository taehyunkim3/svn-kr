import Foundation

public actor SVNClient {
    public init() {}

    public func checkout(repositoryURL: String, destinationPath: String) async throws -> String {
        let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else {
            throw SVNError.commandFailed(command: "svn checkout", message: "저장할 상위 폴더가 존재하지 않습니다.")
        }
        return try checkedRun(["checkout", repositoryURL, destination.path], at: parent.path).output
    }

    public func validateWorkingCopy(at path: String) async throws {
        let result = try run(["info", "--show-item", "wc-root"], at: path)
        guard result.exitCode == 0 else { throw SVNError.invalidWorkingCopy }
    }

    public func status(at path: String) async throws -> [SVNStatusEntry] {
        let result = try checkedRun(["status", "--xml"], at: path)
        return try SVNXMLParser.statuses(from: Data(result.output.utf8))
    }

    public func log(at path: String, limit: Int = 50) async throws -> [SVNLogEntry] {
        let result = try checkedRun(["log", "--xml", "--limit", String(limit)], at: path)
        return try SVNXMLParser.logs(from: Data(result.output.utf8))
    }

    public func update(at path: String) async throws -> String {
        try checkedRun(["update"], at: path).output
    }

    public func diff(at path: String, relativePath: String? = nil) async throws -> String {
        var arguments = ["diff"]
        if let relativePath { arguments.append(relativePath) }
        return try checkedRun(arguments, at: path).output
    }

    public func commit(at path: String, paths: [String], message: String) async throws -> String {
        let currentStatuses = try await status(at: path)
        for item in paths {
            let status = currentStatuses.first(where: { $0.path == item })
            if status?.item == "unversioned" {
                _ = try checkedRun(["add", "--parents", "--", item], at: path)
            } else if status?.item == "missing" {
                _ = try checkedRun(["delete", "--force", "--", item], at: path)
            }
        }
        return try checkedRun(["commit", "--message", message, "--"] + paths, at: path).output
    }

    @discardableResult
    private func checkedRun(_ arguments: [String], at path: String) throws -> SVNCommandResult {
        let result = try run(arguments, at: path)
        guard result.exitCode == 0 else {
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SVNError.commandFailed(command: "svn \(arguments.first ?? "")", message: detail.isEmpty ? result.output : detail)
        }
        return result
    }

    private func run(_ arguments: [String], at path: String) throws -> SVNCommandResult {
        let process = Process()
        process.executableURL = try svnExecutableURL()
        process.arguments = ["--non-interactive"] + arguments
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

        do {
            try process.run()
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
        if let override = ProcessInfo.processInfo.environment["SVN_EXECUTABLE"], !override.isEmpty {
            candidates.append(override)
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
}
