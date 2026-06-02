import Foundation
import Security
import CryptoKit

/// Process-global store for pinned TLS leaf-certificate hashes. Wraps a single
/// `CredentialStore` so pins persist in the Keychain (or the encrypted file
/// fallback) and survive relaunches. The lock keeps concurrent TLS handshakes
/// from racing on the learn-on-first-use write.
enum TLSPinningStore {
    nonisolated(unsafe) private static let store = CredentialStore()
    private static let lock = NSLock()

    static func pin(host: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return store.tlsPin(host: host)
    }

    static func learn(_ hash: Data, host: String) {
        lock.lock(); defer { lock.unlock() }
        store.saveTLSPin(hash, host: host)
    }
}

/// A `URLSession` delegate that allows self-signed / otherwise untrusted server
/// certificates **only for an explicit allowlist of hosts**, and even then pins
/// the certificate so it can't be silently swapped by a man-in-the-middle.
///
/// Security model:
/// - Relaxing TLS validation is opt-in per instance and scoped to that
///   instance's configured hosts. Any host not in the allowlist still goes
///   through the system's default certificate validation, so a misconfiguration
///   can never silently weaken security for unrelated connections.
/// - For an allowed host, the leaf certificate's SHA-256 is pinned on first
///   contact (Trust-On-First-Use). On every later connection the certificate
///   must match the pin; if it changed, the connection is **refused** — an
///   attacker presenting their own self-signed certificate is rejected. If the
///   user deliberately regenerated the certificate, they reset the pin in the
///   service settings.
final class SelfSignedTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    private let allowedHosts: Set<String>

    init(allowedHosts: Set<String>) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host.lowercased()
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              allowedHosts.contains(host) else {
            // Not a server-trust challenge for an allowed host — use the default
            // handling (full validation).
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Extract the leaf certificate and hash its DER encoding.
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leaf = chain.first else {
            // No presentable certificate — refuse rather than blindly trust.
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let der = SecCertificateCopyData(leaf) as Data
        let presentedHash = Data(SHA256.hash(data: der))

        if let pinned = TLSPinningStore.pin(host: host) {
            if pinned == presentedHash {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                // Certificate changed since it was pinned — possible MITM.
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            // First contact for this self-signed host: pin it, then trust it.
            TLSPinningStore.learn(presentedHash, host: host)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }
}
