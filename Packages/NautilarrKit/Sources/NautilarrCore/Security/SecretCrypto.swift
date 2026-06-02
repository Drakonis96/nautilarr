import Foundation
import CryptoKit
import CommonCrypto

/// Symmetric encryption helpers for protecting secrets at rest (the local secret
/// store) and in transit (the exported configuration bundle). Uses AES-GCM with
/// a 256-bit key; passphrase-based variants derive the key via PBKDF2-HMAC-SHA256.
public enum SecretCrypto {
    public enum CryptoError: Error, Equatable, Sendable { case wrongPassphrase, malformed }

    /// Magic prefix marking a Nautilarr passphrase-encrypted blob.
    private static let magic = Data("NAUT1".utf8)
    private static let saltLength = 16
    private static let pbkdfRounds: UInt32 = 210_000

    // MARK: Key-based (for the local file store)

    public static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw CryptoError.malformed }
        return combined
    }

    public static func open(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: Passphrase-based (for config export/import)

    /// Encrypts `plaintext` with a key derived from `passphrase`. Output is
    /// `magic || salt(16) || AES-GCM(combined)`.
    public static func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        let salt = randomBytes(saltLength)
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw CryptoError.malformed }
        return magic + salt + combined
    }

    public static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        guard data.count > magic.count + saltLength, data.prefix(magic.count) == magic else {
            throw CryptoError.malformed
        }
        let salt = data.subdata(in: magic.count ..< magic.count + saltLength)
        let combined = data.subdata(in: magic.count + saltLength ..< data.count)
        let key = deriveKey(passphrase: passphrase, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.wrongPassphrase
        }
    }

    /// Whether `data` looks like a Nautilarr passphrase-encrypted blob.
    public static func isEncrypted(_ data: Data) -> Bool {
        data.prefix(magic.count) == magic
    }

    // MARK: Internals

    private static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let passwordCount = passphrase.utf8.count
        _ = saltBytes.withUnsafeBufferPointer { saltBuf in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passphrase, passwordCount,
                saltBuf.baseAddress, saltBuf.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                pbkdfRounds,
                &derived, derived.count
            )
        }
        return SymmetricKey(data: Data(derived))
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for i in 0..<count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }
}
