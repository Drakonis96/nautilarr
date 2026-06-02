import Foundation
import CryptoKit

/// A file-backed `SecretStoring` used as a fallback when the Keychain is
/// unavailable — e.g. an ad-hoc-signed Mac Catalyst build without keychain
/// entitlements, where `SecItemAdd` returns `errSecMissingEntitlement`.
///
/// Hardening (defence-in-depth, since this is weaker than the Keychain):
/// - Contents are **encrypted with AES-GCM** (never stored in plaintext).
/// - The encryption key lives in the Keychain when possible; otherwise in a
///   protected key file.
/// - **App Lock:** when a master password is set, the store key is *wrapped* with
///   a password-derived key (`credentials.lock`) and the unprotected copies are
///   removed. Until the user unlocks, the store key is unavailable and secrets
///   can't be read — so a stolen disk/backup is useless without the password.
/// - Files use owner-only POSIX permissions (0600), are excluded from backups,
///   and request complete file protection on iOS.
public final class FileSecretStore: SecretStoring, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    // Shared across all instances so the unlock state (and the resolved key) is
    // process-global. All stores share one key (per the fixed key file / Keychain
    // account), so this is consistent regardless of `filename`.
    private static let stateLock = NSLock()
    private static var sessionKey: SymmetricKey?
    private static let keychain = KeychainStore(service: "com.drakonis96.nautilarr.filekey")

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nautilarr", isDirectory: true)
    }
    private static var keyURL: URL { directory.appendingPathComponent("credentials.key") }
    private static var lockURL: URL { directory.appendingPathComponent("credentials.lock") }

    public init(filename: String = "credentials.store") {
        let support = Self.directory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
        Self.excludeFromBackup(support)
        self.url = support.appendingPathComponent(filename)
        if !Self.isAppLockEnabled {
            _ = Self.resolveRandomKey()   // populate sessionKey (unchanged behaviour)
            migratePlaintextIfNeeded()
        }
    }

    /// If an older build left a plaintext store on disk, re-write it encrypted.
    private func migratePlaintextIfNeeded() {
        guard let key = Self.currentKey(),
              let raw = try? Data(contentsOf: url), !raw.isEmpty,
              (try? SecretCrypto.open(raw, key: key)) == nil,
              let dict = try? JSONDecoder().decode([String: Data].self, from: raw) else { return }
        saveAll(dict)
    }

    // MARK: Storage

    private func loadAll() -> [String: Data] {
        lock.lock(); defer { lock.unlock() }
        guard let key = Self.currentKey(), let raw = try? Data(contentsOf: url) else { return [:] }
        if let plaintext = try? SecretCrypto.open(raw, key: key),
           let dict = try? JSONDecoder().decode([String: Data].self, from: plaintext) {
            return dict
        }
        // Legacy plaintext store (pre-encryption) — read so nothing is lost.
        if let dict = try? JSONDecoder().decode([String: Data].self, from: raw) {
            return dict
        }
        return [:]
    }

    private func saveAll(_ dict: [String: Data]) {
        lock.lock(); defer { lock.unlock() }
        guard let key = Self.currentKey(),
              let plaintext = try? JSONEncoder().encode(dict),
              let ciphertext = try? SecretCrypto.seal(plaintext, key: key) else { return }
        try? ciphertext.write(to: url, options: [.atomic])
        Self.protect(url)
    }

    public func set(_ data: Data, for account: String) throws {
        var dict = loadAll(); dict[account] = data; saveAll(dict)
    }
    public func data(for account: String) throws -> Data? { loadAll()[account] }
    public func remove(for account: String) throws {
        var dict = loadAll(); dict[account] = nil; saveAll(dict)
    }

    // MARK: Key resolution

    private static func currentKey() -> SymmetricKey? {
        stateLock.lock(); defer { stateLock.unlock() }
        return sessionKey
    }

    /// Resolves the random store key (Keychain → key file → generate). Used when
    /// App Lock is OFF. Caches into `sessionKey`.
    @discardableResult
    private static func resolveRandomKey() -> SymmetricKey? {
        stateLock.lock(); defer { stateLock.unlock() }
        if let sessionKey { return sessionKey }
        if let data = try? keychain.data(for: "fileStoreKey"), data.count == 32 {
            sessionKey = SymmetricKey(data: data); return sessionKey
        }
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            sessionKey = SymmetricKey(data: data); return sessionKey
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        if (try? keychain.set(keyData, for: "fileStoreKey")) != nil,
           (try? keychain.data(for: "fileStoreKey")) == keyData {
            sessionKey = newKey; return newKey
        }
        try? keyData.write(to: keyURL, options: [.atomic]); protect(keyURL)
        sessionKey = newKey
        return newKey
    }

    // MARK: App Lock (master password)

    /// Whether a master password protects the store (the key is wrapped on disk).
    public static var isAppLockEnabled: Bool {
        FileManager.default.fileExists(atPath: lockURL.path)
    }

    /// Whether secrets are currently accessible (App Lock off, or unlocked).
    public static var isUnlocked: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return sessionKey != nil || !isAppLockEnabled
    }

    /// Unlocks the store with the master password. Returns `false` on wrong password.
    @discardableResult
    public static func unlock(password: String) -> Bool {
        guard isAppLockEnabled else { return true }
        guard let blob = try? Data(contentsOf: lockURL),
              let keyData = try? SecretCrypto.decrypt(blob, passphrase: password), keyData.count == 32 else {
            return false
        }
        stateLock.lock(); sessionKey = SymmetricKey(data: keyData); stateLock.unlock()
        return true
    }

    /// Re-locks the store (drops the in-memory key).
    public static func relock() {
        stateLock.lock(); sessionKey = nil; stateLock.unlock()
    }

    /// Turns App Lock on: wraps the current store key with the password and
    /// deletes the unprotected key copies. Requires the store to be unlocked.
    @discardableResult
    public static func enableAppLock(password: String) -> Bool {
        guard !password.isEmpty, let key = resolveRandomKey() ?? currentKey() else { return false }
        let keyData = key.withUnsafeBytes { Data($0) }
        guard let blob = try? SecretCrypto.encrypt(keyData, passphrase: password) else { return false }
        guard (try? blob.write(to: lockURL, options: [.atomic])) != nil else { return false }
        protect(lockURL)
        try? FileManager.default.removeItem(at: keyURL)
        try? keychain.remove(for: "fileStoreKey")
        stateLock.lock(); sessionKey = key; stateLock.unlock()  // stay unlocked this session
        return true
    }

    /// Turns App Lock off: unwraps the key with the password and restores the
    /// unprotected key copy.
    @discardableResult
    public static func disableAppLock(password: String) -> Bool {
        guard isAppLockEnabled else { return true }
        guard let blob = try? Data(contentsOf: lockURL),
              let keyData = try? SecretCrypto.decrypt(blob, passphrase: password), keyData.count == 32 else {
            return false
        }
        if (try? keychain.set(keyData, for: "fileStoreKey")) == nil || (try? keychain.data(for: "fileStoreKey")) != keyData {
            try? keyData.write(to: keyURL, options: [.atomic]); protect(keyURL)
        }
        try? FileManager.default.removeItem(at: lockURL)
        stateLock.lock(); sessionKey = SymmetricKey(data: keyData); stateLock.unlock()
        return true
    }

    /// Changes the master password (re-wraps the key). Requires the old password.
    @discardableResult
    public static func changePassword(old: String, new: String) -> Bool {
        guard unlock(password: old), let key = currentKey(), !new.isEmpty else { return false }
        let keyData = key.withUnsafeBytes { Data($0) }
        guard let blob = try? SecretCrypto.encrypt(keyData, passphrase: new),
              (try? blob.write(to: lockURL, options: [.atomic])) != nil else { return false }
        protect(lockURL)
        return true
    }

    // MARK: On-disk protection

    private static func protect(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        excludeFromBackup(url)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }
}
