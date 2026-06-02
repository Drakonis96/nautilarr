import XCTest
@testable import NautilarrCore

/// In-memory `SecretStoring` so credential round-tripping can be tested without
/// the system Keychain (which is unavailable / entitlement-gated in CI).
final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func set(_ data: Data, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = data
    }
    func data(for account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }
    func remove(for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }
}

final class CredentialStoreTests: XCTestCase {
    func testRoundTripsAPIKey() throws {
        let store = CredentialStore(store: InMemorySecretStore())
        let id = UUID()
        try store.save(.apiKey("abc123"), for: id)
        XCTAssertEqual(try store.credential(for: id), .apiKey("abc123"))
    }

    func testRoundTripsUsernamePassword() throws {
        let store = CredentialStore(store: InMemorySecretStore())
        let id = UUID()
        try store.save(.usernamePassword(username: "admin", password: "pw"), for: id)
        XCTAssertEqual(try store.credential(for: id), .usernamePassword(username: "admin", password: "pw"))
    }

    func testDeleteRemovesCredential() throws {
        let store = CredentialStore(store: InMemorySecretStore())
        let id = UUID()
        try store.save(.apiKey("x"), for: id)
        try store.delete(for: id)
        XCTAssertNil(try store.credential(for: id))
    }

    func testMissingCredentialReturnsNil() throws {
        let store = CredentialStore(store: InMemorySecretStore())
        XCTAssertNil(try store.credential(for: UUID()))
    }

    func testAuthorizerFactoryProducesHeaderAuthorizerForSonarr() {
        let authorizer = AuthorizerFactory.make(for: .sonarr, credential: .apiKey("k"))
        XCTAssertTrue(authorizer is APIKeyHeaderAuthorizer)
    }

    func testSSHHostKeyRoundTripsAndDeletes() throws {
        let store = CredentialStore(store: InMemorySecretStore())
        let id = UUID()
        XCTAssertNil(store.sshHostKey(for: id))
        let key = Data([0x01, 0x02, 0x03])
        store.saveSSHHostKey(key, for: id)
        XCTAssertEqual(store.sshHostKey(for: id), key)
        store.deleteSSHHostKey(for: id)
        XCTAssertNil(store.sshHostKey(for: id))
    }

    func testTLSPinRoundTripsAndIsHostScoped() throws {
        let store = CredentialStore(store: InMemorySecretStore())
        let hashA = Data([0xAA, 0xBB])
        store.saveTLSPin(hashA, host: "Media.Local")
        // Host lookup is case-insensitive.
        XCTAssertEqual(store.tlsPin(host: "media.local"), hashA)
        // A different host has no pin.
        XCTAssertNil(store.tlsPin(host: "other.local"))
        store.deleteTLSPin(host: "media.local")
        XCTAssertNil(store.tlsPin(host: "media.local"))
    }

    func testFileFallbackStorePersistsCredentials() throws {
        // The file fallback (used when the Keychain is unavailable) must
        // round-trip credentials so services keep working.
        let file = FileSecretStore(filename: "credentials-test-\(UUID().uuidString).store")
        let store = CredentialStore(store: file)
        let id = UUID()
        try store.save(.apiKey("file-key"), for: id)
        XCTAssertEqual(try store.credential(for: id), .apiKey("file-key"))
        try store.delete(for: id)
        XCTAssertNil(try store.credential(for: id))
    }
}
