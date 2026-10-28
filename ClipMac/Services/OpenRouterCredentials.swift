import Foundation
import Security

enum OpenRouterCredentials {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.michael.clip.openrouter",
            kSecAttrAccount as String: "api-key",
            kSecAttrSynchronizable as String: false
        ]
    }

    static func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw CredentialError.keychain(status)
        }
        return key
    }

    static func containsKey() throws -> Bool {
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
        return true
    }

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialError.emptyKey }
        let attributes = [kSecValueData as String: Data(trimmed.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }

    enum CredentialError: LocalizedError {
        case emptyKey
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyKey: "Enter your OpenRouter API key first."
            case let .keychain(status): "Clip couldn’t access the OpenRouter key in Keychain (\(status))."
            }
        }
    }
}
