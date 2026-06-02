import Foundation

/// A configured connection to a single self-hosted service.
///
/// This value is safe to persist (e.g. via `Codable` to disk / UserDefaults) —
/// it deliberately contains **no secrets**. API keys, passwords and SSH keys are
/// stored separately in the system Keychain and referenced by `id`. See
/// `CredentialStore`.
public struct ServiceInstance: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var type: ServiceType
    /// User-facing name, e.g. "Home Sonarr".
    public var name: String

    // MARK: Connectivity

    /// Primary host — typically a LAN address (e.g. `192.168.1.10` or
    /// `nas.local`). May include a scheme and path; it is normalised when the
    /// base URL is built.
    public var primaryHost: String
    /// Optional fallback host — typically a WAN address or DNS name used when
    /// the LAN host is unreachable (e.g. `home.example.com`).
    public var fallbackHost: String?
    /// TCP port. If `nil`, the service's `defaultPort` is used.
    public var port: Int?
    /// Optional reverse-proxy path prefix (e.g. `/sonarr`).
    public var urlBase: String?
    public var useHTTPS: Bool
    /// When `true`, TLS validation is relaxed **for this instance's hosts only**
    /// (self-signed certificates). Off by default.
    public var allowSelfSignedCertificates: Bool

    // MARK: Headers

    /// Extra HTTP headers sent on every request — e.g. Cloudflare Access
    /// (`CF-Access-Client-Id` / `CF-Access-Client-Secret`) or Basic auth in
    /// front of a reverse proxy. Secret-bearing headers should prefer the
    /// Keychain; these are convenience headers stored alongside the instance.
    public var customHeaders: [String: String]

    // MARK: Connectivity preferences

    /// How the active host is chosen at request time.
    public enum HostSelection: String, Codable, Sendable, CaseIterable {
        /// Pick automatically based on the current network (LAN vs. other).
        case automatic
        /// Always use the primary host.
        case forcePrimary
        /// Always use the fallback host.
        case forceFallback
    }
    public var hostSelection: HostSelection

    /// Request timeout in seconds.
    public var timeout: TimeInterval

    /// The network profile this instance belongs to (see `ServiceNetwork`).
    /// Optional for backward compatibility; `nil` instances are migrated into
    /// the default network on load.
    public var networkID: UUID?

    public init(
        id: UUID = UUID(),
        type: ServiceType,
        name: String,
        primaryHost: String,
        fallbackHost: String? = nil,
        port: Int? = nil,
        urlBase: String? = nil,
        useHTTPS: Bool = false,
        allowSelfSignedCertificates: Bool = false,
        customHeaders: [String: String] = [:],
        hostSelection: HostSelection = .automatic,
        timeout: TimeInterval = 30,
        networkID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.primaryHost = primaryHost
        self.fallbackHost = fallbackHost
        self.port = port
        self.urlBase = urlBase
        self.useHTTPS = useHTTPS
        self.allowSelfSignedCertificates = allowSelfSignedCertificates
        self.customHeaders = customHeaders
        self.hostSelection = hostSelection
        self.timeout = timeout
        self.networkID = networkID
    }

    /// Effective port, falling back to the service default.
    public var effectivePort: Int { port ?? type.defaultPort }
}

// MARK: - Base URL construction

public extension ServiceInstance {
    /// Builds a base URL for a given host string, applying the instance's
    /// scheme, port and path prefix.
    ///
    /// The host is parsed leniently: a user may paste a bare host
    /// (`192.168.1.10`), a host:port (`nas.local:8989`) or a full URL
    /// (`https://sonarr.example.com/sonarr`). Any scheme/port/path embedded in
    /// the host string takes precedence over the instance defaults.
    func baseURL(for rawHost: String) -> URL? {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If the user pasted a full URL, honour it as-is (plus urlBase).
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            guard var components = URLComponents(string: trimmed) else { return nil }
            appendURLBase(to: &components)
            return components.url
        }

        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"

        // Split optional `host:port` and optional `/path`.
        var hostPart = trimmed
        var pathPart = ""
        if let slash = hostPart.firstIndex(of: "/") {
            pathPart = String(hostPart[slash...])
            hostPart = String(hostPart[..<slash])
        }

        if let colon = hostPart.lastIndex(of: ":"),
           let explicitPort = Int(hostPart[hostPart.index(after: colon)...]) {
            components.host = String(hostPart[..<colon])
            components.port = explicitPort
        } else {
            components.host = hostPart
            components.port = effectivePort
        }

        components.path = normalisedPath(pathPart)
        appendURLBase(to: &components)
        return components.url
    }

    /// Ordered list of base URLs to try, honouring the host-selection policy and
    /// (when automatic) the supplied network preference.
    ///
    /// - Parameter preferFallbackFirst: when host selection is `.automatic`,
    ///   pass `true` to try the fallback (WAN) host before the primary (LAN)
    ///   host — typically because the device is not on the LAN.
    func candidateBaseURLs(preferFallbackFirst: Bool = false) -> [URL] {
        let primary = baseURL(for: primaryHost)
        let fallback = fallbackHost.flatMap { $0.isEmpty ? nil : baseURL(for: $0) }

        switch hostSelection {
        case .forcePrimary:
            return [primary].compactMap { $0 }
        case .forceFallback:
            return [fallback].compactMap { $0 }
        case .automatic:
            let ordered = preferFallbackFirst ? [fallback, primary] : [primary, fallback]
            return ordered.compactMap { $0 }
        }
    }

    private func appendURLBase(to components: inout URLComponents) {
        guard let urlBase, !urlBase.isEmpty else { return }
        let base = normalisedPath(urlBase)
        // Avoid double slashes when concatenating existing path + urlBase.
        let existing = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = existing + base
    }

    private func normalisedPath(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, p != "/" else { return "" }
        if !p.hasPrefix("/") { p = "/" + p }
        if p.hasSuffix("/") { p = String(p.dropLast()) }
        return p
    }
}
