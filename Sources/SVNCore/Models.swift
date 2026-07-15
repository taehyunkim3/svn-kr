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
    public let email: String?
    public let date: Date?
    public let message: String
    public let changedPaths: [SVNChangedPath]
    public let revisionProperties: [SVNRevisionProperty]

    public var id: String { revision }

    public init(
        revision: String,
        author: String,
        email: String? = nil,
        date: Date?,
        message: String,
        changedPaths: [SVNChangedPath] = [],
        revisionProperties: [SVNRevisionProperty] = []
    ) {
        self.revision = revision
        self.author = author
        self.email = email
        self.date = date
        self.message = message
        self.changedPaths = changedPaths
        self.revisionProperties = revisionProperties
    }
}

public struct SVNChangedPath: Identifiable, Hashable, Sendable {
    public let path: String
    public let action: String
    public let kind: String?
    public let copyFromPath: String?
    public let copyFromRevision: String?
    public let textModified: String?
    public let propertiesModified: String?

    public var id: String { "\(action):\(path)" }

    public init(
        path: String,
        action: String,
        kind: String? = nil,
        copyFromPath: String? = nil,
        copyFromRevision: String? = nil,
        textModified: String? = nil,
        propertiesModified: String? = nil
    ) {
        self.path = path
        self.action = action
        self.kind = kind
        self.copyFromPath = copyFromPath
        self.copyFromRevision = copyFromRevision
        self.textModified = textModified
        self.propertiesModified = propertiesModified
    }
}

public struct SVNRevisionProperty: Identifiable, Hashable, Sendable {
    public let name: String
    public let value: String

    public var id: String { name }

    public init(name: String, value: String) {
        self.name = name
        self.value = value
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
            "선택한 폴더는 SVN 로컬 작업 폴더가 아닙니다."
        case .malformedResponse:
            "SVN 응답을 읽지 못했습니다."
        case .svnExecutableNotFound:
            "앱에 포함된 SVN 실행 파일을 찾지 못했습니다. 앱을 다시 설치해 주세요."
        }
    }
}
