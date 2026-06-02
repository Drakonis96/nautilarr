import Foundation
import NautilarrCore

/// Client for the qBittorrent WebUI API (v2). Uses the generic `APIClient` with
/// a stateful `QBittorrentAuthorizer` (cookie login).
///
/// API reference (public, official):
/// https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)
public struct QBittorrentClient: Sendable {
    private let api: APIClient
    private static let base = "api/v2"

    public init(api: APIClient) { self.api = api }

    /// Builds a client wired to a cookie-login authorizer for the instance.
    public init(instance: ServiceInstance, credential: Credential) {
        let urls = instance.candidateBaseURLs()
        let hosts = Set(urls.compactMap { $0.host })
        var username = ""
        var password = ""
        if case let .usernamePassword(u, p) = credential { username = u; password = p }
        let authorizer = QBittorrentAuthorizer(baseURL: urls.first, username: username, password: password)
        self.api = APIClient(
            baseURLProvider: { urls },
            authorizer: authorizer,
            extraHeaders: instance.customHeaders,
            allowSelfSignedHosts: instance.allowSelfSignedCertificates ? hosts : [],
            timeout: instance.timeout
        )
    }

    // MARK: Connection test

    /// qBittorrent returns the version as plain text, not JSON.
    public func version() async throws -> QBVersion {
        let data = try await api.sendReturningData(.get("\(Self.base)/app/version"))
        let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return QBVersion(version: text)
    }

    // MARK: Torrents

    public func torrents(category: String? = nil, filter: String? = nil) async throws -> [QBTorrent] {
        var query: [URLQueryItem] = []
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        if let filter { query.append(URLQueryItem(name: "filter", value: filter)) }
        return try await api.send(.get("\(Self.base)/torrents/info", query: query))
    }

    public func transferInfo() async throws -> QBTransferInfo {
        try await api.send(.get("\(Self.base)/transfer/info"))
    }

    /// Pause torrents. `hashes` is a list of info-hashes, or `nil` for all.
    /// VERIFY: qBittorrent 5.x renamed this to `/torrents/stop`; 4.x uses
    /// `/torrents/pause`. Adjust per the deployed version if needed.
    public func pause(hashes: [String]? = nil) async throws {
        try await api.send(.form("\(Self.base)/torrents/pause", fields: ["hashes": hashesValue(hashes)]))
    }

    public func resume(hashes: [String]? = nil) async throws {
        try await api.send(.form("\(Self.base)/torrents/resume", fields: ["hashes": hashesValue(hashes)]))
    }

    public func delete(hashes: [String], deleteFiles: Bool) async throws {
        try await api.send(.form("\(Self.base)/torrents/delete", fields: [
            "hashes": hashes.joined(separator: "|"),
            "deleteFiles": deleteFiles ? "true" : "false"
        ]))
    }

    /// Adds torrents by magnet link or `.torrent` URL.
    public func add(urls: [String], category: String? = nil) async throws {
        var fields = ["urls": urls.joined(separator: "\n")]
        if let category { fields["category"] = category }
        try await api.send(.form("\(Self.base)/torrents/add", fields: fields))
    }

    public func setCategory(hashes: [String], category: String) async throws {
        try await api.send(.form("\(Self.base)/torrents/setCategory", fields: [
            "hashes": hashes.joined(separator: "|"),
            "category": category
        ]))
    }

    /// Forces a re-check (re-hash) of the given torrents.
    public func recheck(hashes: [String]) async throws {
        try await api.send(.form("\(Self.base)/torrents/recheck", fields: ["hashes": hashes.joined(separator: "|")]))
    }

    private func hashesValue(_ hashes: [String]?) -> String {
        guard let hashes, !hashes.isEmpty else { return "all" }
        return hashes.joined(separator: "|")
    }
}
