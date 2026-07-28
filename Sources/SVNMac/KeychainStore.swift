import Foundation
import Security
import SVNCore

protocol KeychainStoreBackend {
    func read(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainStoreBackend: KeychainStoreBackend {
    func read(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainStore {
    /// 프로젝트 UUID를 계정 키로 사용해 서로 다른 작업 폴더의 비밀번호가
    /// 섞이지 않게 합니다. 비밀번호는 프로젝트 JSON이나 UserDefaults에 저장하지 않습니다.
    private static let service = SVNApplicationSupport.keychainService

    static func password(
        for projectID: UUID,
        backend: any KeychainStoreBackend = SystemKeychainStoreBackend()
    ) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let result = backend.read(query)
        let status = result.status
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result.data else {
            throw KeychainStoreError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(
        _ password: String,
        for projectID: UUID,
        backend: any KeychainStoreBackend = SystemKeychainStoreBackend()
    ) throws {
        guard !password.isEmpty else {
            try deletePassword(for: projectID, backend: backend)
            return
        }
        let itemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
        ]
        let attributes: [String: Any] = [
            kSecAttrLabel as String: "SVN KR - \(projectID.uuidString)",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(password.utf8),
        ]
        // 먼저 기존 항목 갱신을 시도하고, 없을 때만 새 항목을 추가합니다.
        // 이 순서로 중복 Keychain 항목이 생기는 것을 방지합니다.
        let updateStatus = backend.update(itemQuery, attributes: attributes)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError(status: updateStatus)
        }

        let addStatus = backend.add(itemQuery.merging(attributes) { _, new in new })
        guard addStatus == errSecSuccess else { throw KeychainStoreError(status: addStatus) }
    }

    static func deletePassword(
        for projectID: UUID,
        backend: any KeychainStoreBackend = SystemKeychainStoreBackend()
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
        ]
        let status = backend.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }
}

enum KeychainStoreError: LocalizedError {
    case accessDenied
    case operationFailed(OSStatus)

    init(status: OSStatus) {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            self = .accessDenied
        default:
            self = .operationFailed(status)
        }
    }

    var isAccessDenied: Bool {
        if case .accessDenied = self { return true }
        return false
    }

    var errorDescription: String? {
        guard case let .operationFailed(status) = self else {
            return AppLanguage.current.localized("ui.keychain.access.was.denied.c1358e6f")
        }
        let detail = SecCopyErrorMessageString(status, nil) as String?
            ?? AppLanguage.current.localized("ui.unknown.error.745cd1b7")
        return AppLanguage.current.localized("ui.keychain.operation.failed.e456386b", detail)
    }
}
