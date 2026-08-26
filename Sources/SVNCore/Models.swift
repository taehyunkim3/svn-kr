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
    case ignored
    case conflicted
    case replaced
    case obstructed
    case incomplete
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "modified": self = .modified
        case "added": self = .added
        case "deleted": self = .deleted
        case "missing": self = .missing
        case "unversioned": self = .unversioned
        case "ignored": self = .ignored
        case "conflicted": self = .conflicted
        case "replaced": self = .replaced
        case "obstructed": self = .obstructed
        case "incomplete": self = .incomplete
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
        case .ignored: "ignored"
        case .conflicted: "conflicted"
        case .replaced: "replaced"
        case .obstructed: "obstructed"
        case .incomplete: "incomplete"
        case let .unknown(value): value
        }
    }
}

public enum SVNPropertyState: String, Hashable, Sendable {
    case none
    case modified
    case conflicted
}

public enum SVNIgnorePropertyKind: String, Codable, Hashable, Sendable {
    case local
    case global

    public var propertyName: String {
        switch self {
        case .local: "svn:ignore"
        case .global: "svn:global-ignores"
        }
    }
}

/// 디렉터리의 SVN 무시 속성에 저장된 패턴 하나입니다.
public struct SVNIgnoreRule: Identifiable, Hashable, Sendable {
    public let directory: String
    public let pattern: String
    public let propertyKind: SVNIgnorePropertyKind
    public let inheritedFrom: String?

    public var id: String {
        "\(directory):\(propertyKind.rawValue):\(pattern):\(inheritedFrom ?? "")"
    }

    public init(
        directory: String,
        pattern: String,
        propertyKind: SVNIgnorePropertyKind = .local,
        inheritedFrom: String? = nil
    ) {
        self.directory = directory
        self.pattern = pattern
        self.propertyKind = propertyKind
        self.inheritedFrom = inheritedFrom
    }
}

/// 저장소에 즉시 등록되는 파일 잠금 정보입니다.
public struct SVNLockInfo: Identifiable, Hashable, Sendable {
    public let path: String
    public let token: String?
    public let owner: String
    public let comment: String?
    public let created: Date?

    public var id: String { path }

    public init(path: String, token: String? = nil, owner: String, comment: String? = nil, created: Date? = nil) {
        self.path = path
        self.token = token
        self.owner = owner
        self.comment = comment
        self.created = created
    }
}

/// `svn info --xml` 이 한 경로에 대해 내보내는 `<conflict>` 요소 하나입니다.
/// 같은 파일에 내용 충돌과 속성 충돌이 동시에 나면 요소가 여러 개 옵니다.
public struct SVNConflictRecord: Hashable, Sendable {
    public let type: String
    public let operation: String
    public let previousBaseFile: String?
    public let myFile: String?
    public let serverFile: String?
    public let previousRevision: String?
    public let serverRevision: String?
    public let treeConflictAction: String?
    public let treeConflictReason: String?
    public let treeConflictKind: String?

    public init(
        type: String,
        operation: String,
        previousBaseFile: String? = nil,
        myFile: String? = nil,
        serverFile: String? = nil,
        previousRevision: String? = nil,
        serverRevision: String? = nil,
        treeConflictAction: String? = nil,
        treeConflictReason: String? = nil,
        treeConflictKind: String? = nil
    ) {
        self.type = type
        self.operation = operation
        self.previousBaseFile = previousBaseFile
        self.myFile = myFile
        self.serverFile = serverFile
        self.previousRevision = previousRevision
        self.serverRevision = serverRevision
        self.treeConflictAction = treeConflictAction
        self.treeConflictReason = treeConflictReason
        self.treeConflictKind = treeConflictKind
    }

    /// 해결 화면을 고르는 우선순위입니다. 트리 충돌은 전용 화면이 필요하고,
    /// 내용 충돌은 작업 파일을 덮어쓸 수 있어 속성 충돌보다 먼저 다뤄야 합니다.
    var resolutionPriority: Int {
        switch type {
        case "tree": 0
        case "text": 1
        case "property": 2
        default: 3
        }
    }
}

public struct SVNConflictDetails: Identifiable, Hashable, Sendable {
    public let path: String
    /// 화면 분기에 쓰는 대표 충돌 유형입니다. `conflicts` 중 우선순위가 가장 높은 것입니다.
    public let type: String
    public let operation: String
    public let previousBaseFile: String?
    public let myFile: String?
    public let serverFile: String?
    public let previousRevision: String?
    public let serverRevision: String?
    public let treeConflictAction: String?
    public let treeConflictReason: String?
    public let treeConflictKind: String?
    /// 같은 경로에 동시에 존재하는 충돌 전부입니다. 대표 유형이 맨 앞입니다.
    public let conflicts: [SVNConflictRecord]

    public var id: String { path }

    public var conflictTypes: [String] { conflicts.map(\.type) }
    public var hasTextConflict: Bool { conflicts.contains { $0.type == "text" } }
    public var hasPropertyConflict: Bool { conflicts.contains { $0.type == "property" } }
    public var hasTreeConflict: Bool { conflicts.contains { $0.type == "tree" } }

    public init(
        path: String,
        type: String,
        operation: String,
        previousBaseFile: String? = nil,
        myFile: String? = nil,
        serverFile: String? = nil,
        previousRevision: String? = nil,
        serverRevision: String? = nil,
        treeConflictAction: String? = nil,
        treeConflictReason: String? = nil,
        treeConflictKind: String? = nil,
        conflicts: [SVNConflictRecord] = []
    ) {
        self.path = path
        self.type = type
        self.operation = operation
        self.previousBaseFile = previousBaseFile
        self.myFile = myFile
        self.serverFile = serverFile
        self.previousRevision = previousRevision
        self.serverRevision = serverRevision
        self.treeConflictAction = treeConflictAction
        self.treeConflictReason = treeConflictReason
        self.treeConflictKind = treeConflictKind
        // 목록을 넘기지 않은 호출부는 단일 충돌로 취급합니다.
        // 평면 필드만 아는 경로(예: 경로 접두사 재구성)에서도 목록이 비지 않게 합니다.
        self.conflicts = conflicts.isEmpty
            ? [SVNConflictRecord(
                type: type,
                operation: operation,
                previousBaseFile: previousBaseFile,
                myFile: myFile,
                serverFile: serverFile,
                previousRevision: previousRevision,
                serverRevision: serverRevision,
                treeConflictAction: treeConflictAction,
                treeConflictReason: treeConflictReason,
                treeConflictKind: treeConflictKind
            )]
            : conflicts
    }

    /// 파서가 모은 `<conflict>` 요소 목록에서 대표 유형과 평면 필드를 정합니다.
    /// 평면 필드는 대표 충돌 값을 쓰고, 대표에 없는 보조 파일·리비전만 다른 충돌에서 채웁니다.
    public init?(path: String, conflicts: [SVNConflictRecord]) {
        let ordered = conflicts.enumerated().sorted { left, right in
            left.element.resolutionPriority == right.element.resolutionPriority
                ? left.offset < right.offset
                : left.element.resolutionPriority < right.element.resolutionPriority
        }.map(\.element)
        guard let primary = ordered.first else { return nil }

        func firstValue(_ field: (SVNConflictRecord) -> String?) -> String? {
            field(primary) ?? ordered.lazy.compactMap(field).first
        }

        self.init(
            path: path,
            type: primary.type,
            operation: primary.operation,
            previousBaseFile: firstValue(\.previousBaseFile),
            myFile: firstValue(\.myFile),
            serverFile: firstValue(\.serverFile),
            previousRevision: firstValue(\.previousRevision),
            serverRevision: firstValue(\.serverRevision),
            treeConflictAction: primary.treeConflictAction,
            treeConflictReason: primary.treeConflictReason,
            treeConflictKind: primary.treeConflictKind,
            conflicts: ordered
        )
    }
}

public enum SVNConflictChoice: String, Sendable {
    case working
    case mineFull = "mine-full"
    case theirsFull = "theirs-full"
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
    public let nodeKind: SVNNodeKind?
    public let propertyState: SVNPropertyState
    public let isSwitched: Bool

    public var id: String { path }

    public init(
        path: String,
        item: SVNStatusKind,
        revision: String? = nil,
        nodeKind: SVNNodeKind? = nil,
        propertyState: SVNPropertyState = .none,
        isSwitched: Bool = false
    ) {
        self.path = path
        self.item = item
        self.revision = revision
        self.nodeKind = nodeKind
        self.propertyState = propertyState
        self.isSwitched = isSwitched
    }
}

public extension SVNStatusEntry {
    var isMissingScheduledAddition: Bool {
        item == .missing && (revision == nil || revision == "-1")
    }

    var canScheduleRepositoryDeletion: Bool {
        item == .missing && !isMissingScheduledAddition
    }

    var isSelectableForCommit: Bool {
        item != .missing
            && item != .ignored
            && item != .conflicted
            && propertyState != .conflicted
    }
}

public struct SVNDeletionResult: Hashable, Sendable {
    public let scheduledPaths: [String]
    public let failedPaths: [String]

    public init(scheduledPaths: [String], failedPaths: [String]) {
        self.scheduledPaths = scheduledPaths
        self.failedPaths = failedPaths
    }
}

/// 전체 작업 복사본 탐색기에서 사용하는 경로 상태입니다.
///
/// 기존 `SVNStatusEntry`는 변경된 경로만 표현합니다. 이 모델은
/// `svn status --verbose --no-ignore --xml`의 정상 경로까지 보존해 파일이
/// 저장소 관리 대상인지 판단할 수 있게 합니다.
public struct SVNWorkingCopyEntry: Identifiable, Hashable, Sendable {
    public let path: String
    public let status: String
    public let revision: String?
    public let treeConflicted: Bool
    public let repositoryPath: String?
    public let propertyState: SVNPropertyState
    public let isSwitched: Bool

    public var id: String { path }
    public var repositoryRelativePath: String { repositoryPath ?? path }
    public var isVersioned: Bool {
        status != "unversioned"
            && status != "ignored"
            && status != "external"
            && revision.flatMap(Int.init).map { $0 >= 0 } == true
    }

    public init(
        path: String,
        status: String,
        revision: String? = nil,
        treeConflicted: Bool = false,
        repositoryPath: String? = nil,
        propertyState: SVNPropertyState = .none,
        isSwitched: Bool = false
    ) {
        self.path = path
        self.status = status
        self.revision = revision
        self.treeConflicted = treeConflicted
        self.repositoryPath = repositoryPath
        self.propertyState = propertyState
        self.isSwitched = isSwitched
    }
}

/// 한 작업 복사본에 포함된 버전 관리 항목의 최소·최대 기준 리비전입니다.
///
/// SVN은 일부 항목만 커밋하면 작업 복사본을 혼합 리비전으로 유지하므로,
/// 루트 디렉터리의 단일 리비전만으로는 현재 상태를 정확히 설명할 수 없습니다.
public struct SVNWorkingCopyRevision: Equatable, Sendable {
    public let minimum: String
    public let maximum: String

    public var isMixed: Bool { minimum != maximum }
    public var displayValue: String { isMixed ? "\(minimum)–\(maximum)" : maximum }
    public var timelineRevision: String { maximum }

    public init(minimum: String, maximum: String) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// 서버의 커밋 한 건과 그 커밋에 포함된 상세 변경 정보를 표현합니다.
public struct SVNLogEntry: Identifiable, Hashable, Sendable {
    public let revision: String
    public let author: String
    public let email: String?
    public let date: Date?
    public let message: String
    public let originalMessage: String?
    public let changedPaths: [SVNChangedPath]
    public let revisionProperties: [SVNRevisionProperty]

    public var id: String { revision }

    public init(
        revision: String,
        author: String,
        email: String? = nil,
        date: Date?,
        message: String,
        originalMessage: String? = nil,
        changedPaths: [SVNChangedPath] = [],
        revisionProperties: [SVNRevisionProperty] = []
    ) {
        self.revision = revision
        self.author = author
        self.email = email
        self.date = date
        self.message = message
        self.originalMessage = originalMessage
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

/// CLI 실행과 XML 해석 과정에서 상위 계층이 구분해 처리해야 하는 의미 오류입니다.
/// 사용자 표시 문구는 앱 계층에서 언어와 화면 맥락에 맞게 결정합니다.
public enum SVNError: Error, Sendable {
    case commandFailed(command: String, message: String)
    case workingCopyOutOfDate(details: String)
    case invalidWorkingCopy
    case malformedResponse
    case pathNormalizationCollision(paths: [String])
    case pathAliasRepairFailed(paths: [String])
    case fileReplacementRecoveryFailed(paths: [String], backupPaths: [String])
    case unsupportedTargetPath(paths: [String])
    case unresolvedMissingPaths(paths: [String])
    case deletionValidationFailed(paths: [String])
    case commitSucceededWithValidationWarning(output: String, details: String)
    case recoveryBlocked(paths: [String])
    case recoveryDestinationNotEmpty
    case recoveryValidationFailed(paths: [String])
    case svnExecutableNotFound

}
