import Foundation

public struct SVNStatusEntry: Identifiable, Hashable, Sendable {
    public let path: String
    public let item: String
    public let revision: String?

    public var id: String { path }

    public init(path: String, item: String, revision: String? = nil) {
        self.path = path
        self.item = item
        self.revision = revision
    }
}

public struct SVNLogEntry: Identifiable, Hashable, Sendable {
    public let revision: String
    public let author: String
    public let date: Date?
    public let message: String

    public var id: String { revision }

    public init(revision: String, author: String, date: Date?, message: String) {
        self.revision = revision
        self.author = author
        self.date = date
        self.message = message
    }
}

public struct SVNCommandResult: Sendable {
    public let output: String
    public let error: String
    public let exitCode: Int32

    public init(output: String, error: String, exitCode: Int32) {
        self.output = output
        self.error = error
        self.exitCode = exitCode
    }
}

public struct SVNCredentials: Sendable {
    public let username: String
    public let password: String?

    public init(username: String, password: String? = nil) {
        self.username = username
        self.password = password
    }
}

public enum SVNError: LocalizedError, Sendable {
    case commandFailed(command: String, message: String)
    case invalidWorkingCopy
    case malformedResponse
    case svnExecutableNotFound

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, message):
            "\(command) 실패: \(message)"
        case .invalidWorkingCopy:
            "선택한 폴더는 SVN 작업 복사본이 아닙니다."
        case .malformedResponse:
            "SVN 응답을 읽지 못했습니다."
        case .svnExecutableNotFound:
            "SVN 실행 파일을 찾지 못했습니다. Homebrew에서 subversion을 설치해 주세요."
        }
    }
}
