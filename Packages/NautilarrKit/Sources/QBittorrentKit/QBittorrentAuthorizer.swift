import Foundation
import NautilarrCore

/// Stateful cookie-session authorizer for the qBittorrent WebUI API.
///
/// qBittorrent authenticates by POSTing credentials to `/api/v2/auth/login`,
/// which returns a `SID` cookie. The cookie is stored by the shared
/// `URLSession` and attached to subsequent requests automatically; this
/// authorizer just ensures a valid session exists (logging in lazily and again
/// after a 403). It also sets the `Referer` header qBittorrent requires.
///
/// This exercises the async/stateful side of `RequestAuthorizer` (login round
/// trip + `handleAuthenticationFailure` retry) introduced for Phase 2.
public final class QBittorrentAuthorizer: RequestAuthorizer, @unchecked Sendable {
    private let baseURL: URL?
    private let username: String
    private let password: String
    private let lock = NSLock()
    private var loggedIn = false

    public init(baseURL: URL?, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    private var isLoggedIn: Bool {
        lock.lock(); defer { lock.unlock() }
        return loggedIn
    }
    private func setLoggedIn(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        loggedIn = value
    }

    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {
        if !isLoggedIn { try await login(using: session) }
        if let baseURL { request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer") }
    }

    public func handleAuthenticationFailure(using session: URLSession) async -> Bool {
        setLoggedIn(false)
        do { try await login(using: session); return true } catch { return false }
    }

    private func login(using session: URLSession) async throws {
        guard let baseURL else { throw APIError.invalidBaseURL }
        let loginURL = baseURL.appendingPathComponent("api/v2/auth/login")
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data("username=\(Self.encode(username))&password=\(Self.encode(password))".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let text = String(data: data, encoding: .utf8) ?? ""
        switch http.statusCode {
        case 200 where text.localizedCaseInsensitiveContains("ok"):
            setLoggedIn(true)
        case 403:
            // Too many failed attempts → temporarily banned.
            throw APIError.forbidden
        default:
            throw APIError.unauthorized
        }
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
