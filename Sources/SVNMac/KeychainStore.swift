import Foundation
import Security

enum KeychainStore {
    /// 프로젝트 UUID를 계정 키로 사용해 서로 다른 작업 폴더의 비밀번호가
    /// 섞이지 않게 합니다. 비밀번호는 프로젝트 JSON이나 UserDefaults에 저장하지 않습니다.
    private static let service = "com.mrdevello.svnmac.credentials"

    static func password(for projectID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for projectID: UUID) throws {
        guard !password.isEmpty else {
            try deletePassword(for: projectID)
            return
        }
        let itemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
        ]
        let attributes: [String: Any] = [
            kSecAttrLabel as String: "SVN Mac - \(projectID.uuidString)",
            kSecValueData as String: Data(password.utf8),
        ]
        // 먼저 기존 항목 갱신을 시도하고, 없을 때만 새 항목을 추가합니다.
        // 이 순서로 중복 Keychain 항목이 생기는 것을 방지합니다.
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError(status: updateStatus)
        }

        let addAttributes = attributes.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]) { _, new in new }
        let addStatus = SecItemAdd(itemQuery.merging(addAttributes) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainStoreError(status: addStatus) }
    }

    static func deletePassword(for projectID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
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
            return AppLanguage.current.text(
                "Keychain 접근이 거부되었습니다.",
                "Keychain access was denied."
            )
        }
        let detail = SecCopyErrorMessageString(status, nil) as String?
            ?? AppLanguage.current.text("알 수 없는 오류", "Unknown error")
        return AppLanguage.current.text("Keychain 처리 실패: \(detail)", "Keychain operation failed: \(detail)")
    }
}
