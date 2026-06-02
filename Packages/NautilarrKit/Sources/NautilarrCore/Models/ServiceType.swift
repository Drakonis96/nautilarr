import Foundation

/// The catalog of self-hosted services Nautilarr can talk to.
///
/// Only generic, descriptive identifiers are used — no commercial product is
/// named in a way that implies affiliation. Each case maps to a public REST API
/// that Nautilarr integrates against. Integrations are delivered in phases; see
/// `phase` for the roadmap bucket each one belongs to.
public enum ServiceType: String, Codable, CaseIterable, Sendable, Identifiable {
    // Phase 1 — core media management (*arr family)
    case sonarr
    case radarr
    case lidarr

    // Phase 2 — requests & download clients
    case overseerr
    case qbittorrent
    case sabnzbd
    case nzbget
    case transmission
    case deluge

    // Phase 3 — monitoring & advanced
    case tautulli
    case jellystat
    case prowlarr
    case nzbhydra2
    case jackett
    case bazarr
    case unraid
    case ssh

    public var id: String { rawValue }

    /// Roadmap phase this integration belongs to.
    public enum Phase: Int, Sendable, Comparable {
        case core = 1
        case downloads = 2
        case monitoring = 3
        public static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var phase: Phase {
        switch self {
        case .sonarr, .radarr, .lidarr:
            return .core
        case .overseerr, .qbittorrent, .sabnzbd, .nzbget, .transmission, .deluge:
            return .downloads
        case .tautulli, .jellystat, .prowlarr, .nzbhydra2, .jackett, .bazarr, .unraid, .ssh:
            return .monitoring
        }
    }

    /// Human-facing label shown in the UI.
    public var displayName: String {
        switch self {
        case .sonarr: return "Sonarr"
        case .radarr: return "Radarr"
        case .lidarr: return "Lidarr"
        case .overseerr: return "Overseerr / Jellyseerr"
        case .qbittorrent: return "qBittorrent"
        case .sabnzbd: return "SABnzbd"
        case .nzbget: return "NZBGet"
        case .transmission: return "Transmission"
        case .deluge: return "Deluge"
        case .tautulli: return "Tautulli"
        case .jellystat: return "Jellystat"
        case .prowlarr: return "Prowlarr"
        case .nzbhydra2: return "NZBHydra2"
        case .jackett: return "Jackett"
        case .bazarr: return "Bazarr"
        case .unraid: return "Unraid"
        case .ssh: return "SSH / SFTP"
        }
    }

    /// Short category descriptor for grouping in settings.
    public var category: String {
        switch phase {
        case .core: return "Media Management"
        case .downloads: return "Requests & Downloads"
        case .monitoring: return "Monitoring & Servers"
        }
    }

    /// Asset-catalog name of the bundled official service logo (a vector PDF).
    /// `nil` for services without a specific logo (e.g. SSH), which fall back to
    /// `symbolName`. Logos identify the service you connect to (nominative use).
    public var logoAssetName: String? {
        switch self {
        case .ssh: return nil
        default: return "service-\(rawValue)"
        }
    }

    /// SF Symbol used as the fallback glyph for the service.
    public var symbolName: String {
        switch self {
        case .sonarr: return "tv"
        case .radarr: return "film"
        case .lidarr: return "music.note"
        case .overseerr: return "sparkle.magnifyingglass"
        case .qbittorrent, .transmission, .deluge: return "arrow.down.circle"
        case .sabnzbd, .nzbget: return "tray.and.arrow.down"
        case .tautulli, .jellystat: return "chart.bar.xaxis"
        case .prowlarr, .nzbhydra2, .jackett: return "magnifyingglass.circle"
        case .bazarr: return "captions.bubble"
        case .unraid: return "server.rack"
        case .ssh: return "terminal"
        }
    }

    /// Default TCP port the service usually listens on (best-effort default;
    /// always user-overridable).
    public var defaultPort: Int {
        switch self {
        case .sonarr: return 8989
        case .radarr: return 7878
        case .lidarr: return 8686
        case .overseerr: return 5055
        case .qbittorrent: return 8080
        case .sabnzbd: return 8080
        case .nzbget: return 6789
        case .transmission: return 9091
        case .deluge: return 8112
        case .tautulli: return 8181
        case .jellystat: return 3000
        case .prowlarr: return 9696
        case .nzbhydra2: return 5076
        case .jackett: return 9117
        case .bazarr: return 6767
        case .unraid: return 443
        case .ssh: return 22
        }
    }

    /// The authentication scheme the API expects. Drives the credential form.
    public var authenticationKind: AuthenticationKind {
        switch self {
        case .sonarr, .radarr, .lidarr, .prowlarr, .bazarr:
            return .apiKeyHeader(headerName: "X-Api-Key")
        case .overseerr:
            return .apiKeyHeader(headerName: "X-Api-Key")
        case .sabnzbd, .tautulli, .nzbhydra2, .jackett:
            return .apiKeyQuery(parameterName: "apikey")
        case .jellystat:
            // Jellystat validates an API key via the `x-api-token` header.
            return .apiKeyHeader(headerName: "x-api-token")
        case .qbittorrent, .deluge:
            return .cookieSession
        case .nzbget:
            return .basicAuth
        case .transmission:
            return .transmissionSession
        case .unraid:
            return .apiKeyHeader(headerName: "x-api-key")
        case .ssh:
            return .sshCredentials
        }
    }
}

/// Describes how a service authenticates, so the UI can present the right form
/// and the networking layer can attach the right `RequestAuthorizer`.
public enum AuthenticationKind: Sendable, Equatable {
    case apiKeyHeader(headerName: String)
    case apiKeyQuery(parameterName: String)
    case basicAuth
    case cookieSession
    case transmissionSession
    case sshCredentials
}
