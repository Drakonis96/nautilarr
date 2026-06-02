import XCTest
import CryptoKit
@testable import NautilarrCore

final class SecretCryptoTests: XCTestCase {
    func testPassphraseRoundTrip() throws {
        let secret = Data("X-Api-Key: super-secret-12345".utf8)
        let blob = try SecretCrypto.encrypt(secret, passphrase: "correct horse battery staple")
        XCTAssertTrue(SecretCrypto.isEncrypted(blob))
        XCTAssertNotEqual(blob, secret)
        XCTAssertFalse(blob.contains(Data("super-secret".utf8)))   // plaintext not present
        let out = try SecretCrypto.decrypt(blob, passphrase: "correct horse battery staple")
        XCTAssertEqual(out, secret)
    }

    func testWrongPassphraseFails() throws {
        let blob = try SecretCrypto.encrypt(Data("hello".utf8), passphrase: "right")
        XCTAssertThrowsError(try SecretCrypto.decrypt(blob, passphrase: "wrong")) { error in
            XCTAssertEqual(error as? SecretCrypto.CryptoError, .wrongPassphrase)
        }
    }

    func testIsEncryptedRejectsPlainJSON() {
        XCTAssertFalse(SecretCrypto.isEncrypted(Data("{\"a\":1}".utf8)))
    }

    func testKeyRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let secret = Data("credentials.store contents".utf8)
        let sealed = try SecretCrypto.seal(secret, key: key)
        XCTAssertNotEqual(sealed, secret)
        XCTAssertEqual(try SecretCrypto.open(sealed, key: key), secret)
        // A different key must not decrypt.
        XCTAssertThrowsError(try SecretCrypto.open(sealed, key: SymmetricKey(size: .bits256)))
    }
}
