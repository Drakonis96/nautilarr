import Foundation
import NIOCore
import NIOSSH
import Citadel
import CryptoKit
import NautilarrCore

/// SSH host-key validator. It NEVER blindly trusts a server (unlike Citadel's
/// `.acceptAnything`, which would leak the password to an impostor):
/// - If a key is already pinned, it must match exactly — otherwise the handshake
///   is aborted **before the password is sent** (`.mismatch`).
/// - On the first connection there is no pinned key, so it captures the key and
///   aborts with `.unverified` so the app can show the fingerprint for the user
///   to confirm before anything is trusted.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    enum Outcome: Sendable { case ok, mismatch, unverified }

    private let expected: Data?
    private let lock = NSLock()
    private var _outcome: Outcome = .ok
    private var _captured: Data?

    init(expected: Data?) { self.expected = expected }

    var outcome: Outcome { lock.lock(); defer { lock.unlock() }; return _outcome }
    var capturedKey: Data? { lock.lock(); defer { lock.unlock() }; return _captured }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        _ = hostKey.write(to: &buffer)
        let presented = Data(buffer.readableBytesView)
        lock.lock(); _captured = presented; lock.unlock()

        if let expected {
            if expected == presented {
                validationCompletePromise.succeed(())
            } else {
                lock.lock(); _outcome = .mismatch; lock.unlock()
                validationCompletePromise.fail(SSHSession.SSHError.hostKeyChanged)
            }
        } else {
            // First contact: do NOT auto-trust — abort so the user can verify the
            // fingerprint. No password is sent (host key is checked before auth).
            lock.lock(); _outcome = .unverified; lock.unlock()
            validationCompletePromise.fail(SSHSession.SSHError.hostKeyChanged)
        }
    }
}

/// A file/directory entry returned by the SFTP browser.
public struct SSHFileEntry: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?

    public init(name: String, path: String, isDirectory: Bool, size: Int64?) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
    }
}

/// Wraps a Citadel SSH connection (pure-Swift, SwiftNIO SSH). An `actor` so the
/// underlying client is accessed serially. Provides command execution (host
/// stats, Docker, processes) and a minimal SFTP browser/reader.
///
/// Host-key validation uses **verify-before-trust pinning** (`TOFUHostKeyValidator`):
/// on the first connection the handshake is aborted before authentication and
/// the fingerprint is surfaced for the user to confirm; once pinned, the key
/// must match exactly thereafter. A man-in-the-middle therefore can't impersonate
/// the server and capture the password. Password authentication is supported in
/// this phase; key-based auth is a follow-up.
public actor SSHSession {
    public enum SSHError: Error, LocalizedError {
        case notConfigured
        case hostKeyChanged
        /// First connection to this host — the user must verify the fingerprint.
        case hostKeyUnverified(fingerprint: String, key: Data)
        case message(String)
        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "SSH credentials are not configured."
            case .hostKeyChanged:
                return "The SSH host key changed since you last connected. This can mean a man-in-the-middle attack — Nautilarr refused to connect and did NOT send your password. If you deliberately rebuilt the server, reset the trusted host key in the service settings."
            case let .hostKeyUnverified(fingerprint, _):
                return "First connection to this server. Verify this host-key fingerprint matches your server before trusting it:\n\(fingerprint)"
            case let .message(text): return text
            }
        }
    }

    private let host: String
    private let port: Int
    private let username: String
    private let password: String
    private let timeout: TimeInterval
    private let knownHostKeyProvider: (@Sendable () -> Data?)?
    private var client: SSHClient?

    public init(instance: ServiceInstance, credential: Credential, timeout: TimeInterval = 30,
                knownHostKeyProvider: (@Sendable () -> Data?)? = nil) {
        self.knownHostKeyProvider = knownHostKeyProvider
        let parsed = SSHSession.parseHostPort(instance.primaryHost, defaultPort: instance.effectivePort, explicitPort: instance.port)
        self.host = parsed.host
        self.port = parsed.port
        self.timeout = timeout
        if case let .ssh(user, pass, _) = credential {
            self.username = user
            self.password = pass ?? ""
        } else if case let .usernamePassword(user, pass) = credential {
            self.username = user
            self.password = pass
        } else {
            self.username = ""
            self.password = ""
        }
    }

    /// Parses an SSH host string into a host + port, honouring an embedded
    /// `host:port`, then an explicit instance port, then the default. Exposed
    /// for unit testing.
    public static func parseHostPort(_ raw: String, defaultPort: Int, explicitPort: Int?) -> (host: String, port: Int) {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if let schemeRange = value.range(of: "://") { value = String(value[schemeRange.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        if let colon = value.lastIndex(of: ":"), let embedded = Int(value[value.index(after: colon)...]) {
            return (String(value[..<colon]), embedded)
        }
        return (value, explicitPort ?? defaultPort)
    }

    private func connectedClient() async throws -> SSHClient {
        if let client { return client }
        guard !username.isEmpty else { throw SSHError.notConfigured }
        let validator = TOFUHostKeyValidator(expected: knownHostKeyProvider?())
        do {
            let client = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: .passwordBased(username: username, password: password),
                hostKeyValidator: .custom(validator),
                reconnect: .never,
                connectTimeout: .seconds(Int64(timeout))
            )
            self.client = client
            return client
        } catch {
            // A host-key problem is a security event, not a generic failure.
            switch validator.outcome {
            case .mismatch:
                throw SSHError.hostKeyChanged
            case .unverified:
                if let key = validator.capturedKey {
                    throw SSHError.hostKeyUnverified(fingerprint: Self.fingerprint(of: key), key: key)
                }
                throw SSHError.message(error.localizedDescription)
            case .ok:
                throw SSHError.message(error.localizedDescription)
            }
        }
    }

    /// OpenSSH-style SHA256 fingerprint of a serialized host key.
    public static func fingerprint(of key: Data) -> String {
        let digest = SHA256.hash(data: key)
        let b64 = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(b64)"
    }

    // MARK: - Operations

    /// Runs a command and returns its combined stdout/stderr as text.
    @discardableResult
    public func run(_ command: String) async throws -> String {
        let client = try await connectedClient()
        do {
            let buffer = try await client.executeCommand(command, mergeStreams: true)
            return String(buffer: buffer)
        } catch {
            throw SSHError.message(error.localizedDescription)
        }
    }

    /// Lists a directory over SFTP (directories first, then files, alphabetical).
    public func list(_ path: String) async throws -> [SSHFileEntry] {
        let client = try await connectedClient()
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }
        let listings = try await sftp.listDirectory(atPath: path)

        var entries: [SSHFileEntry] = []
        for listing in listings {
            for component in listing.components {
                let name = component.filename
                if name == "." || name == ".." { continue }
                let isDirectory = component.longname.first == "d"
                let full = path.hasSuffix("/") ? path + name : path + "/" + name
                entries.append(SSHFileEntry(
                    name: name,
                    path: full,
                    isDirectory: isDirectory,
                    size: component.attributes.size.map(Int64.init)
                ))
            }
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Reads a (text) file over SFTP, capped to `maxBytes`.
    public func readTextFile(_ path: String, maxBytes: UInt32 = 256 * 1024) async throws -> String {
        let client = try await connectedClient()
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }
        let buffer = try await sftp.withFile(filePath: path, flags: .read) { file in
            try await file.read(from: 0, length: maxBytes)
        }
        return String(buffer: buffer)
    }

    public func disconnect() async {
        try? await client?.close()
        client = nil
    }
}
