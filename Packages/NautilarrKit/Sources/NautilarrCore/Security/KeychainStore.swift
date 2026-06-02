import Foundation
import Security

/// Errors surfaced by `KeychainStore`.
public enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
}

/// Abstraction over a small secret store so higher layers (e.g.
/// `CredentialStore`) can be unit-tested with an in-memory backing instead of
/// the real Keychain.
public protocol SecretStoring: Sendable {
    func set(_ data: Data, for account: String) throws
    func data(for account: String) throws -> Data?
    func remove(for account: String) throws
}

/// A minimal wrapper around the system Keychain for storing small secrets as
/// generic passwords.
///
/// Deliberately uses **no Keychain access group / App Group** — those require a
/// paid provisioning profile entitlement, which is incompatible with the free
/// 7-day signing certificate Nautilarr targets. Items are therefore scoped to
/// the app's own default access group, which works on iOS, iPadOS and
/// Mac Catalyst without special entitlements.
public struct KeychainStore: SecretStoring, Sendable {
    /// The `kSecAttrService` namespace for all items written by this store.
    public let service: String

    /// Items are only readable after first unlock and never sync to iCloud
    /// Keychain (which would need an entitlement). This keeps secrets on-device.
    private var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    public init(service: String = "com.drakonis96.nautilarr.credentials") {
        self.service = service
    }

    /// Stores (or replaces) `data` under `account`.
    public func set(_ data: Data, for account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try to update an existing item first.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessibility
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
            return
        }

        throw KeychainError.unexpectedStatus(updateStatus)
    }

    /// Convenience for storing a UTF-8 string.
    public func setString(_ string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else { throw KeychainError.dataConversionFailed }
        try set(data, for: account)
    }

    /// Reads the raw data for `account`, or `nil` if absent.
    public func data(for account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the item for `account` (no error if it does not exist).
    public func remove(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes every item in this store's service namespace.
    public func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
