import Foundation
import Security
import Testing
@testable import SVNMac

@Test func existingKeychainItemUpdatesAccessibilityClass() throws {
    let backend = StubKeychainBackend(updateStatus: errSecSuccess)
    let projectID = UUID()

    try KeychainStore.setPassword("secret", for: projectID, backend: backend)

    #expect(backend.updatedAttributes?[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleAfterFirstUnlock as String)
    #expect(backend.addedAttributes == nil)
}

@Test func newKeychainItemIncludesAccessibilityAndSecretData() throws {
    let backend = StubKeychainBackend(updateStatus: errSecItemNotFound)
    let projectID = UUID()

    try KeychainStore.setPassword("secret", for: projectID, backend: backend)

    #expect(backend.addedAttributes?[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleAfterFirstUnlock as String)
    #expect(backend.addedAttributes?[kSecValueData as String] as? Data == Data("secret".utf8))
}

@Test func emptyPasswordDeletesExistingKeychainItem() throws {
    let backend = StubKeychainBackend(updateStatus: errSecSuccess)

    try KeychainStore.setPassword("", for: UUID(), backend: backend)

    #expect(backend.deleteCallCount == 1)
    #expect(backend.updatedAttributes == nil)
}

private final class StubKeychainBackend: KeychainStoreBackend {
    let updateStatus: OSStatus
    var updatedAttributes: [String: Any]?
    var addedAttributes: [String: Any]?
    var deleteCallCount = 0

    init(updateStatus: OSStatus) {
        self.updateStatus = updateStatus
    }

    func read(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        (errSecItemNotFound, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updatedAttributes = attributes
        return updateStatus
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addedAttributes = attributes
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCallCount += 1
        return errSecSuccess
    }
}
