import SwiftUI

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
    case requests
    case indexers
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
        case .requests: return "Requests"
        case .indexers: return "Indexers"
        case .subtitles: return "Subtitles"
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
        case .requests: return "tray.and.arrow.down"
        case .indexers: return "magnifyingglass.circle"
        case .subtitles: return "captions.bubble"
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
            } else {
                Image(systemName: symbol)
            }
        }
    }

    /// Whether this destination shows the active-downloads badge.
    var showsActivityBadge: Bool { self == .downloads }

    /// Whether the user may hide this destination from the sidebar/tab bar.
    /// Home and Settings always stay visible so the app is never stranded.
    var canHide: Bool {
        switch self {
        case .home, .settings: return false
        default: return true
        }
    }
}
