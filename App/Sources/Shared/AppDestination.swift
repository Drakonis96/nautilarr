import SwiftUI
import NautilarrCore

/// The top-level navigation destinations, shown as a sidebar on iPad/Mac and a
/// tab bar on iPhone.
enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case plex
    case jellyfin
    case library
    case subtitles
    case calendar
    case search
    case downloads
    case inbox
    case requests
    case indexers
    case tautulli
    case jellystat
    case unraid
    case statainer
    case ssh
    case server
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .plex: return "Plex"
        case .jellyfin: return "Jellyfin"
        case .library: return "Library"
        case .calendar: return "Calendar"
        case .search: return "Search"
        case .downloads: return "Downloads"
        case .inbox: return "Activity"
        case .requests: return "Requests"
        case .indexers: return "Indexers"
        case .subtitles: return "Subtitles"
        case .tautulli: return "Tautulli"
        case .jellystat: return "Jellystat"
        case .unraid: return "Unraid"
        case .statainer: return "Statainer"
        case .ssh: return "SSH / SFTP"
        case .server: return "Server"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .plex: return "play.rectangle.fill"
        case .jellyfin: return "play.circle.fill"
        case .library: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .search: return "magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .inbox: return "bell.badge"
        case .requests: return "tray.and.arrow.down"
        case .indexers: return "magnifyingglass.circle"
        case .subtitles: return "captions.bubble"
        case .tautulli: return "chart.bar.xaxis"
        case .jellystat: return "chart.bar.xaxis"
        case .unraid: return "server.rack"
        case .statainer: return "shippingbox"
        case .ssh: return "terminal"
        case .server: return "server.rack"
        case .settings: return "gearshape"
        }
    }

    /// The media shortcut this destination represents, if any.
    var mediaShortcut: MediaShortcut? {
        switch self {
        case .plex: return .plex
        case .jellyfin: return .jellyfin
        default: return nil
        }
    }

    /// The bundled service logo shown in navigation for service-specific
    /// destinations (Tautulli/Jellystat/Unraid). `nil` falls back to the SF Symbol.
    var serviceLogoAsset: String? {
        switch self {
        case .tautulli: return "service-tautulli"
        case .jellystat: return "service-jellystat"
        case .unraid: return "service-unraid"
        case .statainer: return "service-statainer"
        default: return nil
        }
    }

    /// Service type this destination is bound to — the section only appears when
    /// at least one instance of it is configured. `nil` = always available.
    var requiredServiceType: ServiceType? {
        switch self {
        case .tautulli: return .tautulli
        case .jellystat: return .jellystat
        case .unraid: return .unraid
        case .statainer: return .statainer
        case .ssh: return .ssh
        default: return nil
        }
    }

    /// Whether this destination should be shown given the configured services.
    @MainActor
    func isConfigured(in store: InstanceStore) -> Bool {
        guard let type = requiredServiceType else { return true }
        return !store.instances(ofType: type).isEmpty
    }

    /// Navigation label — uses the service's coloured logo for media shortcuts,
    /// otherwise the SF Symbol.
    @ViewBuilder var navLabel: some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            if let shortcut = mediaShortcut {
                Image(shortcut.logoAssetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else if let asset = serviceLogoAsset {
                Image(asset)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: symbol)
            }
        }
    }

    /// Whether this destination shows a count badge in the sidebar/tab bar.
    var showsActivityBadge: Bool { self == .downloads || self == .inbox }

    /// The badge count to show for this destination, resolved from live counts.
    @MainActor func badgeCount(in environment: AppEnvironment) -> Int {
        switch self {
        case .downloads: return environment.activeDownloadCount
        case .inbox: return environment.inboxIssueCount
        default: return 0
        }
    }

    /// Whether the user may hide this destination from the sidebar/tab bar.
    /// Home and Settings always stay visible so the app is never stranded.
    var canHide: Bool {
        switch self {
        case .home, .settings: return false
        default: return true
        }
    }
}
