import AppKit
import Foundation
import SVNCore

// MARK: - SVN 명령 인터페이스

/// ProjectStore가 구체적인 SVNClient actor 대신 의존하는 기능 계약입니다.
/// 테스트에서는 같은 계약을 구현한 가짜 클라이언트로 느린 응답과 실패를 재현합니다.
protocol SVNClientServing: Sendable {
    func checkout(repositoryURL: String, destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String
    func checkout(repositoryURL: String, destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool, progress: SVNOutputHandler?) async throws -> String
    func validateWorkingCopy(at path: String, credentials: SVNCredentials?) async throws
    func status(at path: String, credentials: SVNCredentials?) async throws -> [SVNStatusEntry]
    func workingCopyEntries(at path: String, credentials: SVNCredentials?) async throws -> [SVNWorkingCopyEntry]
    func workingCopySnapshot(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopySnapshot
    func repairCanonicalAliases(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopySnapshot
    func recoveryPreview(at path: String, credentials: SVNCredentials?) async throws -> SVNRecoveryPreview
    func recoverWorkingCopy(from sourcePath: String, to destinationPath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> SVNRecoveryResult
    func ignoredStatus(at path: String, credentials: SVNCredentials?) async throws -> [SVNStatusEntry]
    func ignoreRules(at path: String, credentials: SVNCredentials?) async throws -> [SVNIgnoreRule]
    func addIgnoreRule(at path: String, directory: String, pattern: String, credentials: SVNCredentials?) async throws
    func removeIgnoreRule(at path: String, directory: String, pattern: String, credentials: SVNCredentials?) async throws
    func repositoryLocks(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLockInfo]
    func lockInfo(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> SVNLockInfo?
    func lock(at path: String, relativePath: String, comment: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String
    func unlock(at path: String, relativePath: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String
    func conflictDetails(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> SVNConflictDetails?
    func resolveConflict(at path: String, relativePath: String, choice: SVNConflictChoice, credentials: SVNCredentials?) async throws -> String
    func log(at path: String, limit: Int, endingAtRevision: String?, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLogEntry]
    func revisionDiff(at path: String, revision: String, repositoryPath: String, workingCopyRepositoryPath: String?, pegRevision: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String
    func workingCopyRevision(at path: String, credentials: SVNCredentials?) async throws -> SVNWorkingCopyRevision
    func workingCopyRepositoryPath(at path: String, credentials: SVNCredentials?) async throws -> String
    func workingCopyIsOutOfDate(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> Bool
    func remoteChanges(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNStatusEntry]
    func update(at path: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String
    func diff(at path: String, relativePath: String?, credentials: SVNCredentials?) async throws -> String
    func revert(at path: String, relativePath: String, credentials: SVNCredentials?) async throws -> String
    func fileLog(at path: String, relativePath: String, limit: Int, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> [SVNLogEntry]
    func commit(at path: String, paths: [String], message: String, credentials: SVNCredentials?, allowUntrustedServerCertificate: Bool) async throws -> String
}

extension SVNClientServing {
    func checkout(
        repositoryURL: String,
        destinationPath: String,
        credentials: SVNCredentials?,
        allowUntrustedServerCertificate: Bool,
        progress: SVNOutputHandler?
    ) async throws -> String {
        let output = try await checkout(
            repositoryURL: repositoryURL,
            destinationPath: destinationPath,
            credentials: credentials,
            allowUntrustedServerCertificate: allowUntrustedServerCertificate
        )
        progress?(output)
        return output
    }
}

extension SVNClient: SVNClientServing {}

// MARK: - 자격 증명 저장소

/// 비밀번호 저장 위치를 ProjectStore에서 분리합니다.
/// 운영 환경은 macOS Keychain을 사용하고 테스트는 메모리 구현을 주입합니다.
protocol CredentialStoring {
    func password(for projectID: UUID) throws -> String?
    func setPassword(_ password: String, for projectID: UUID) throws
    func deletePassword(for projectID: UUID) throws
}

struct KeychainCredentialStore: CredentialStoring {
    func password(for projectID: UUID) throws -> String? { try KeychainStore.password(for: projectID) }
    func setPassword(_ password: String, for projectID: UUID) throws { try KeychainStore.setPassword(password, for: projectID) }
    func deletePassword(for projectID: UUID) throws { try KeychainStore.deletePassword(for: projectID) }
}

// MARK: - 프로젝트 목록 영속화

/// 프로젝트 배열의 저장 위치를 추상화해 테스트가 실제 UserDefaults를 오염시키지 않게 합니다.
protocol ProjectPersisting {
    func loadProjects() -> [SVNProject]
    func saveProjects(_ projects: [SVNProject])
}

struct UserDefaultsProjectPersistence: ProjectPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "svn-projects-v1") {
        self.defaults = defaults
        self.key = key
    }

    func loadProjects() -> [SVNProject] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SVNProject].self, from: data)) ?? []
    }

    func saveProjects(_ projects: [SVNProject]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - 보안 범위 폴더 접근

/// App Sandbox용 bookmark 생성과 접근 수명을 한 객체가 소유합니다.
protocol ProjectAccessManaging: AnyObject {
    func makeBookmark(for url: URL) throws -> Data
    func restoreAccess(for projects: inout [SVNProject])
    func beginAccessing(_ url: URL, for projectID: SVNProject.ID)
    func endAccessing(projectID: SVNProject.ID)
    func endAccessing(url: URL)
}

final class SecurityScopedProjectAccessManager: ProjectAccessManaging {
    private var accessedURLs: [SVNProject.ID: URL] = [:]

    func makeBookmark(for url: URL) throws -> Data {
        try url.standardizedFileURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func restoreAccess(for projects: inout [SVNProject]) {
        for index in projects.indices {
            guard let bookmarkData = projects[index].bookmarkData else { continue }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { continue }
            let standardizedURL = url.standardizedFileURL
            projects[index].path = standardizedURL.path
            if isStale, let refreshedBookmark = try? makeBookmark(for: standardizedURL) {
                projects[index].bookmarkData = refreshedBookmark
            }
            beginAccessing(standardizedURL, for: projects[index].id)
        }
    }

    func beginAccessing(_ url: URL, for projectID: SVNProject.ID) {
        guard accessedURLs[projectID] == nil else { return }
        _ = url.startAccessingSecurityScopedResource()
        accessedURLs[projectID] = url
    }

    func endAccessing(projectID: SVNProject.ID) {
        guard let url = accessedURLs.removeValue(forKey: projectID) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func endAccessing(url: URL) {
        guard let entry = accessedURLs.first(where: { $0.value == url }) else { return }
        endAccessing(projectID: entry.key)
    }
}

// MARK: - 파일 열기

@MainActor
protocol WorkspaceOpening {
    func open(_ url: URL) -> Bool
}

struct AppWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
}

// MARK: - 실행 중 작업 모델

/// 단순 busy 여부뿐 아니라 어떤 종류의 작업이 실행 중인지 함께 보존합니다.
struct ProjectOperation: Identifiable, Equatable {
    enum Kind: Equatable {
        case checkout
        case registerProject
        case refresh(SVNProject.ID)
        case refreshHistory(SVNProject.ID)
        case loadMoreHistory(SVNProject.ID)
        case revisionDiff(SVNProject.ID)
        case browseFiles(SVNProject.ID)
        case ignore(SVNProject.ID)
        case lock(SVNProject.ID)
        case resolveConflict(SVNProject.ID)
        case previewUpdate(SVNProject.ID)
        case revert(SVNProject.ID)
        case fileHistory(SVNProject.ID)
        case update(SVNProject.ID)
        case commit(SVNProject.ID)
        case recover(SVNProject.ID)
    }

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}
