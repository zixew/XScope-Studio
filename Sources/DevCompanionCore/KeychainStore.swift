import Foundation
import Security

public protocol SecretStoring: Sendable {
    func saveSecret(_ value: String, account: String) throws
    func loadSecret(account: String) -> String?
    func deleteSecret(account: String) throws
}

/// Stores sensitive API keys in macOS Keychain instead of plaintext UserDefaults.
public struct KeychainStore: SecretStoring {
    private let service: String

    public init(service: String = "com.devcompanion.mac.secrets") {
        self.service = service
    }

    public func saveSecret(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            CompanionLog.security.error("Keychain save failed with status \(status)")
            throw CompanionError.keychainFailure(status: status)
        }
    }

    public func loadSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CompanionError.keychainFailure(status: status)
        }
    }
}
