import Foundation
import Security

/// Secure storage for the Anthropic API key using the macOS Keychain (generic password).
///
/// Constitution IV: the key lives only here, is read on demand, and is never written to
/// config, logs, or any file the app emits.
public protocol KeychainStoring: Sendable {
    func save(_ key: String) throws
    func load() -> String?
    func remove() throws
    var hasKey: Bool { get }
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
        if let msg = SecCopyErrorMessageString(status, nil) as String? {
            return "Keychain error (\(status)): \(msg)"
        }
        return "Keychain error (\(status))"
    }
}

public struct KeychainStore: KeychainStoring {
    public let service: String
    public let account: String

    public init(service: String = "com.sumbee.app",
                account: String = "anthropic-api-key") {
        self.service = service
        self.account = account
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        // Try update first; if not present, add.
        let matchQuery = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            return
        }
        throw KeychainError(status: updateStatus)
    }

    public func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func remove() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    public var hasKey: Bool {
        load()?.isEmpty == false
    }
}
