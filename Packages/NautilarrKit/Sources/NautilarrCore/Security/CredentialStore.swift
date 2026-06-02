import Foundation

/// Stores and retrieves a `Credential` for each `ServiceInstance`, keyed by the
/// instance's `id`. Secrets are encoded as JSON and persisted in the system
/// Keychain when it is usable, with a file-backed fallback otherwise.
///
/// This is the single funnel through which secrets are persisted, keeping the
/// rest of the app free of direct secret-store access and ensuring nothing
/// secret is ever written to `UserDefaults`.
public struct CredentialStore: Sendable {
    private let store: SecretStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Whether secrets are backed by the system Keychain (`true`) or the file
    /// fallback (`false`). Useful for diagnostics/UI.
    public let usesKeychain: Bool

    /// - Parameter store: an explicit backing store (used by tests). When `nil`
    ///   (the default), the Keychain is probed and used if functional; if the
    ///   Keychain is unavailable (e.g. an ad-hoc-signed Mac Catalyst build),
    ///   a `FileSecretStore` is used instead so credentials still persist.
    public init(store: SecretStoring? = nil) {
        if let store {
            self.store = store
            self.usesKeychain = store is KeychainStore
        } else {
            let keychain = KeychainStore()
            if CredentialStore.keychainIsUsable(keychain) {
                self.store = keychain
                self.usesKeychain = true
            } else {
                self.store = FileSecretStore()
                self.usesKeychain = false
            }
        }
    }

    private static func keychainIsUsable(_ keychain: KeychainStore) -> Bool {
        let probe = "nautilarr.keychain.probe"
        let value = Data([0x4E])
        do {
            try keychain.set(value, for: probe)
            let read = try keychain.data(for: probe)
            try? keychain.remove(for: probe)
            return read == value
        } catch {
            return false
        }
    }

    private func account(for instanceID: UUID) -> String { "instance.\(instanceID.uuidString)" }

    public func save(_ credential: Credential, for instanceID: UUID) throws {
        let data = try encoder.encode(credential)
        try store.set(data, for: account(for: instanceID))
    }

    public func credential(for instanceID: UUID) throws -> Credential? {
        guard let data = try store.data(for: account(for: instanceID)) else { return nil }
        return try decoder.decode(Credential.self, from: data)
    }

    public func delete(for instanceID: UUID) throws {
        try store.remove(for: account(for: instanceID))
    }

    // MARK: - SSH known-host keys (host-key pinning / TOFU)
    //
    // Pinned SSH host keys are not secret, but they MUST be tamper-resistant —
    // if an attacker could overwrite the pinned key, MITM protection is defeated.
    // Storing them in the same protected/encrypted store gives that integrity.

    private func hostKeyAccount(for instanceID: UUID) -> String { "sshhost.\(instanceID.uuidString)" }

    public func sshHostKey(for instanceID: UUID) -> Data? {
        try? store.data(for: hostKeyAccount(for: instanceID))
    }
    public func saveSSHHostKey(_ data: Data, for instanceID: UUID) {
        try? store.set(data, for: hostKeyAccount(for: instanceID))
    }
    public func deleteSSHHostKey(for instanceID: UUID) {
        try? store.remove(for: hostKeyAccount(for: instanceID))
    }

    // MARK: - TLS certificate pins (self-signed pinning / TOFU)
    //
    // For hosts where the user opted into self-signed certificates, we pin the
    // leaf certificate's SHA-256 on first contact and require it to match
    // thereafter. Like the SSH host key, the pin isn't secret but MUST be
    // tamper-resistant, so it lives in the same protected store. Keyed by host
    // (a service's self-signed cert is shared across its instances).

    private func tlsPinAccount(for host: String) -> String { "tlscert.\(host.lowercased())" }

    public func tlsPin(host: String) -> Data? {
        try? store.data(for: tlsPinAccount(for: host))
    }
    public func saveTLSPin(_ hash: Data, host: String) {
        try? store.set(hash, for: tlsPinAccount(for: host))
    }
    public func deleteTLSPin(host: String) {
        try? store.remove(for: tlsPinAccount(for: host))
    }
}
