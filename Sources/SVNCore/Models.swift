import Foundation

/// `svn status --xml`의 `item` 값을 앱에서 안전하게 다루기 위한 상태 타입입니다.
///
/// SVN 버전에 따라 새로운 값이 추가될 수 있으므로, 앱이 아직 모르는 값은
/// `unknown`에 원문을 보존합니다. 이렇게 하면 문자열 오타는 컴파일 단계에서
/// 막으면서도 미래의 SVN 응답을 화면에 표시할 수 있습니다.
public enum SVNStatusKind: Hashable, Sendable {
    case modified
    case added
    case deleted
    case missing
    case unversioned
    case conflicted
    case replaced
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "modified": self = .modified
        case "added": self = .added
        case "deleted": self = .deleted
        case "missing": self = .missing
        case "unversioned": self = .unversioned
        case "conflicted": self = .conflicted
        case "replaced": self = .replaced
        default: self = .unknown(rawValue)
        }
    }

    /// 알 수 없는 상태를 포함해 SVN이 사용한 원래 문자열을 반환합니다.
    public var rawValue: String {
        switch self {
        case .modified: "modified"
        case .added: "added"
        case .deleted: "deleted"
        case .missing: "missing"
        case .unversioned: "unversioned"
        case .conflicted: "conflicted"
        case .replaced: "replaced"
        case let .unknown(value): value
        }
    }
}

/// 커밋 기록의 변경 경로에 붙는 SVN 작업 코드입니다.
public enum SVNChangeAction: Hashable, Sendable {
    case added
    case modified
    case deleted
    case replaced
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "A": self = .added
        case "M": self = .modified
        case "D": self = .deleted
        case "R": self = .replaced
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .replaced: "R"
        case let .unknown(value): value
        }
    }
}

/// 변경 경로가 파일인지 폴더인지 나타냅니다.
public enum SVNNodeKind: Hashable, Sendable {
    case file
    case directory
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "file": self = .file
        case "dir": self = .directory
        default: self = .unknown(rawValue)
        }
    }
}

/// 한 작업 복사본 안에서 변경된 경로 하나를 표현합니다.
public struct SVNStatusEntry: Identifiable, Hashable, Sendable {
    public let path: String
    public let item: SVNStatusKind
    public let revision: String?

    public var id: String { path }

    public init(path: String, item: SVNStatusKind, revision: String? = nil) {
        self.path = path
        self.item = item
        self.revision = revision
    }
}

/// 서버의 커밋 한 건과 그 커밋에 포함된 상세 변경 정보를 표현합니다.
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

/// 커밋 한 건에서 변경된 저장소 경로 하나를 표현합니다.
public struct SVNChangedPath: Identifiable, Hashable, Sendable {
    public let path: String
    public let action: SVNChangeAction
    public let kind: SVNNodeKind?
    public let copyFromPath: String?
    public let copyFromRevision: String?
    public let textModified: Bool?
    public let propertiesModified: Bool?

    public var id: String { "\(action.rawValue):\(path)" }

    public init(
        path: String,
        action: SVNChangeAction,
        kind: SVNNodeKind? = nil,
        copyFromPath: String? = nil,
        copyFromRevision: String? = nil,
        textModified: Bool? = nil,
        propertiesModified: Bool? = nil
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

/// `--with-all-revprops`로 받은 표준 속성 외의 사용자 정의 리비전 속성입니다.
public struct SVNRevisionProperty: Identifiable, Hashable, Sendable {
    public let name: String
    public let value: String

    public var id: String { name }

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// SVN 프로세스의 표준 출력, 표준 오류, 종료 코드를 손실 없이 전달합니다.
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

/// 한 SVN 명령에 사용할 인증 정보입니다. 비밀번호는 저장 모델에 포함되지 않고
/// 명령 실행 시점에만 전달됩니다.
public struct SVNCredentials: Sendable {
    public let username: String
    public let password: String?

    public init(username: String, password: String? = nil) {
        self.username = username
        self.password = password
    }
}

/// CLI 실행과 XML 해석 과정에서 화면이 구분해 처리해야 하는 오류입니다.
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
