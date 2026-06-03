import SwiftUI
import Combine

/// User-facing appearance and behaviour preferences. Persisted in
/// `UserDefaults` (no secrets). Observable so the UI updates live.
final class AppSettings: ObservableObject {
    @AppStorage("accentPalette") private var accentRaw: String = AccentPalette.teal.rawValue
    @AppStorage("backgroundPalette") private var backgroundRaw: String = BackgroundPalette.system.rawValue
    @AppStorage("colorScheme") private var colorSchemeRaw: String = AppColorScheme.system.rawValue
    @AppStorage("tabOrder") private var tabOrderRaw: String = ""
    @AppStorage("hiddenTabs") private var hiddenTabsRaw: String = ""
    @AppStorage("tabOrderVersion") private var tabOrderVersionStored: Int = 0
    @AppStorage("textSize") private var textSizeRaw: String = AppTextSize.large.rawValue

    /// Current default-tab-order version. Bump when the built-in order changes so
    /// existing installs adopt it once (their custom reorder is reset that once).
    /// v3 placed the Plex/Jellyfin shortcuts after Home; v4 adds the independent
    /// Tautulli/Jellystat/Unraid/SSH sections before Server.
    private static let currentTabOrderVersion = 4

    init() {
        // One-time migration: adopt the new built-in section order (Subtitles
        // under Library, Indexers under Requests) by clearing the saved order so
        // it falls back to `AppDestination.allCases`.
        if tabOrderVersionStored < Self.currentTabOrderVersion {
            tabOrderRaw = ""
            tabOrderVersionStored = Self.currentTabOrderVersion
        }
        // Apply the saved language override immediately at launch.
        Bundle.setAppLanguage(appLanguageStored.isEmpty ? nil : appLanguageStored)
    }

    /// App-wide text size (Dynamic Type), adjustable in Settings → Appearance.
    var textSize: AppTextSize {
        get { AppTextSize(rawValue: textSizeRaw) ?? .large }
        set { objectWillChange.send(); textSizeRaw = newValue.rawValue }
    }
    @AppStorage("autoRefreshSeconds") var autoRefreshSeconds: Int = 5
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false

    // Appearance — floating buttons (bottom-right, every screen).
    @AppStorage("showScrollToTopButton") private var scrollToTopEnabledStored: Bool = true
    @AppStorage("showQuickNavButton") private var quickNavEnabledStored: Bool = true
    /// Whether the floating scroll-to-top button is shown app-wide.
    var scrollToTopEnabled: Bool {
        get { scrollToTopEnabledStored }
        set { objectWillChange.send(); scrollToTopEnabledStored = newValue }
    }
    /// Whether the floating quick-access (fan) button is shown app-wide.
    var quickNavEnabled: Bool {
        get { quickNavEnabledStored }
        set { objectWillChange.send(); quickNavEnabledStored = newValue }
    }

    // Advanced — networking timeouts (seconds).
    @AppStorage("httpTimeout") private var httpTimeoutStored: Int = 60
    @AppStorage("sshTimeout") private var sshTimeoutStored: Int = 30
    @AppStorage("autoRefreshNowPlaying") private var autoRefreshNowPlayingStored: Bool = true

    // Downloads — seed limit (client-side janitor for torrent clients).
    @AppStorage("seedLimitEnabled") private var seedLimitEnabledStored: Bool = false
    @AppStorage("seedLimitByDays") private var seedLimitByDaysStored: Bool = true
    @AppStorage("maxSeedDays") private var maxSeedDaysStored: Int = 14
    @AppStorage("seedLimitByRatio") private var seedLimitByRatioStored: Bool = false
    @AppStorage("maxSeedRatio") private var maxSeedRatioStored: Double = 2.0
    @AppStorage("seedLimitAction") private var seedLimitActionRaw: String = SeedLimitAction.pause.rawValue
    // Downloads — individually disabled download clients (by instance id).
    @AppStorage("disabledClients") private var disabledClientsRaw: String = ""

    var seedLimitEnabled: Bool {
        get { seedLimitEnabledStored }
        set { objectWillChange.send(); seedLimitEnabledStored = newValue }
    }
    var seedLimitByDays: Bool {
        get { seedLimitByDaysStored }
        set { objectWillChange.send(); seedLimitByDaysStored = newValue }
    }
    /// Maximum number of days a torrent may seed before the chosen action runs.
    var maxSeedDays: Int {
        get { maxSeedDaysStored }
        set { objectWillChange.send(); maxSeedDaysStored = min(365, max(1, newValue)) }
    }
    var seedLimitByRatio: Bool {
        get { seedLimitByRatioStored }
        set { objectWillChange.send(); seedLimitByRatioStored = newValue }
    }
    /// Maximum share ratio a torrent may reach before the chosen action runs.
    var maxSeedRatio: Double {
        get { maxSeedRatioStored }
        set { objectWillChange.send(); maxSeedRatioStored = min(100, max(0.1, (newValue * 100).rounded() / 100)) }
    }
    var seedLimitAction: SeedLimitAction {
        get { SeedLimitAction(rawValue: seedLimitActionRaw) ?? .pause }
        set { objectWillChange.send(); seedLimitActionRaw = newValue.rawValue }
    }

    /// IDs of download-client instances the user has switched off.
    var disabledClientIDs: Set<String> {
        Set(disabledClientsRaw.split(separator: ",").map(String.init))
    }
    func isClientEnabled(_ id: UUID) -> Bool { !disabledClientIDs.contains(id.uuidString) }
    func setClientEnabled(_ id: UUID, _ enabled: Bool) {
        objectWillChange.send()
        var set = disabledClientIDs
        if enabled { set.remove(id.uuidString) } else { set.insert(id.uuidString) }
        disabledClientsRaw = set.sorted().joined(separator: ",")
    }

    // Media shortcuts (Plex / Jellyfin quick links shown as navigation sections).
    @AppStorage("plexEnabled") private var plexEnabledStored = false
    @AppStorage("plexUsesApp") private var plexUsesAppStored = false
    @AppStorage("plexWeb") private var plexWebStored = ""
    @AppStorage("plexApp") private var plexAppStored = "plex://"
    @AppStorage("jellyfinEnabled") private var jellyfinEnabledStored = false
    @AppStorage("jellyfinUsesApp") private var jellyfinUsesAppStored = false
    @AppStorage("jellyfinWeb") private var jellyfinWebStored = ""
    @AppStorage("jellyfinApp") private var jellyfinAppStored = "jellyfin://"

    // Security — biometric gates (LocalAuthentication; on-device only).
    @AppStorage("faceIDForSSH") private var faceIDForSSHStored: Bool = false
    @AppStorage("faceIDForSettings") private var faceIDForSettingsStored: Bool = false
    @AppStorage("faceIDOnLaunch") private var faceIDOnLaunchStored: Bool = false

    var httpTimeout: Int {
        get { httpTimeoutStored }
        set { objectWillChange.send(); httpTimeoutStored = min(300, max(5, newValue)) }
    }
    var sshTimeout: Int {
        get { sshTimeoutStored }
        set { objectWillChange.send(); sshTimeoutStored = min(120, max(5, newValue)) }
    }
    var autoRefreshNowPlaying: Bool {
        get { autoRefreshNowPlayingStored }
        set { objectWillChange.send(); autoRefreshNowPlayingStored = newValue }
    }
    var faceIDForSSH: Bool {
        get { faceIDForSSHStored }
        set { objectWillChange.send(); faceIDForSSHStored = newValue }
    }
    var faceIDForSettings: Bool {
        get { faceIDForSettingsStored }
        set { objectWillChange.send(); faceIDForSettingsStored = newValue }
    }
    var faceIDOnLaunch: Bool {
        get { faceIDOnLaunchStored }
        set { objectWillChange.send(); faceIDOnLaunchStored = newValue }
    }

    // `@AppStorage` already triggers `objectWillChange` for SwiftUI views that
    // read these computed accessors, because the backing wrappers republish.

    var accent: AccentPalette {
        get { AccentPalette(rawValue: accentRaw) ?? .teal }
        set { objectWillChange.send(); accentRaw = newValue.rawValue }
    }

    /// App-wide pastel background wash.
    var background: BackgroundPalette {
        get { BackgroundPalette(rawValue: backgroundRaw) ?? .system }
        set { objectWillChange.send(); backgroundRaw = newValue.rawValue }
    }

    // App language override ("" = follow the system language). Applied on next
    // launch via the standard `AppleLanguages` preference.
    @AppStorage("appLanguage") private var appLanguageStored = ""
    var appLanguage: String {
        get { appLanguageStored }
        set {
            objectWillChange.send()
            appLanguageStored = newValue
            // Apply immediately (no relaunch) by overriding the bundle language…
            Bundle.setAppLanguage(newValue.isEmpty ? nil : newValue)
            // …and persist the standard preference too so a relaunch stays consistent.
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            }
        }
    }

    /// Locale to apply app-wide (drives SwiftUI `Text` lookup + formatting).
    var localeIdentifier: String {
        appLanguage.isEmpty ? Locale.current.identifier : appLanguage
    }

    // MARK: Media shortcuts

    /// Whether a shortcut section is enabled (and therefore shown in navigation).
    func shortcutEnabled(_ kind: MediaShortcut) -> Bool {
        switch kind {
        case .plex: return plexEnabledStored
        case .jellyfin: return jellyfinEnabledStored
        }
    }
    func setShortcutEnabled(_ kind: MediaShortcut, _ value: Bool) {
        objectWillChange.send()
        switch kind {
        case .plex: plexEnabledStored = value
        case .jellyfin: jellyfinEnabledStored = value
        }
    }

    /// `true` to open the native app (URL scheme), `false` to open a web/IP URL.
    func shortcutUsesApp(_ kind: MediaShortcut) -> Bool {
        switch kind {
        case .plex: return plexUsesAppStored
        case .jellyfin: return jellyfinUsesAppStored
        }
    }
    func setShortcutUsesApp(_ kind: MediaShortcut, _ value: Bool) {
        objectWillChange.send()
        switch kind {
        case .plex: plexUsesAppStored = value
        case .jellyfin: jellyfinUsesAppStored = value
        }
    }

    /// The web/IP URL for a shortcut.
    func shortcutWeb(_ kind: MediaShortcut) -> String {
        switch kind {
        case .plex: return plexWebStored
        case .jellyfin: return jellyfinWebStored
        }
    }
    func setShortcutWeb(_ kind: MediaShortcut, _ value: String) {
        objectWillChange.send()
        switch kind {
        case .plex: plexWebStored = value
        case .jellyfin: jellyfinWebStored = value
        }
    }

    /// The native-app URL scheme for a shortcut.
    func shortcutApp(_ kind: MediaShortcut) -> String {
        switch kind {
        case .plex: return plexAppStored
        case .jellyfin: return jellyfinAppStored
        }
    }
    func setShortcutApp(_ kind: MediaShortcut, _ value: String) {
        objectWillChange.send()
        switch kind {
        case .plex: plexAppStored = value
        case .jellyfin: jellyfinAppStored = value
        }
    }

    /// Resolves the URL a shortcut should open, based on its mode.
    func shortcutURL(_ kind: MediaShortcut) -> URL? {
        let raw = (shortcutUsesApp(kind) ? shortcutApp(kind) : shortcutWeb(kind))
            .trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        // Tolerate a bare host/IP in web mode by defaulting to http://.
        if !shortcutUsesApp(kind), !raw.contains("://") { return URL(string: "http://\(raw)") }
        return URL(string: raw)
    }

    /// Whether a destination is currently available to show (disabled media
    /// shortcuts are hidden everywhere until configured).
    func isAvailable(_ destination: AppDestination) -> Bool {
        guard let kind = destination.mediaShortcut else { return true }
        return shortcutEnabled(kind)
    }

    var colorScheme: AppColorScheme {
        get { AppColorScheme(rawValue: colorSchemeRaw) ?? .system }
        set { objectWillChange.send(); colorSchemeRaw = newValue.rawValue }
    }

    /// Persisted ordering of the main navigation destinations.
    var tabOrder: [AppDestination] {
        get {
            let ids = tabOrderRaw.split(separator: ",").map(String.init)
            let restored = ids.compactMap { AppDestination(rawValue: $0) }
            // Append any destinations not yet in the saved order.
            let missing = AppDestination.allCases.filter { !restored.contains($0) }
            return restored.isEmpty ? AppDestination.allCases : restored + missing
        }
        set {
            objectWillChange.send()
            tabOrderRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// Destinations the user has hidden from the sidebar/tab bar.
    var hiddenTabs: Set<AppDestination> {
        get { Set(hiddenTabsRaw.split(separator: ",").compactMap { AppDestination(rawValue: String($0)) }) }
        set {
            objectWillChange.send()
            hiddenTabsRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// The destinations actually shown — ordered, minus any hidden (non-hideable
    /// ones such as Home/Settings always remain) and minus disabled shortcuts.
    var visibleTabOrder: [AppDestination] {
        tabOrder.filter { isAvailable($0) && (!hiddenTabs.contains($0) || !$0.canHide) }
    }

    /// Ordered destinations available for reordering (excludes disabled shortcuts).
    var reorderableTabOrder: [AppDestination] {
        tabOrder.filter { isAvailable($0) }
    }

    /// Reorders only the available destinations, keeping disabled shortcuts parked
    /// at the end so they reappear in place once enabled.
    func applyReorder(_ newOrder: [AppDestination]) {
        let unavailable = tabOrder.filter { !isAvailable($0) }
        tabOrder = newOrder + unavailable
    }

    func isHidden(_ destination: AppDestination) -> Bool {
        destination.canHide && hiddenTabs.contains(destination)
    }

    func toggleHidden(_ destination: AppDestination) {
        guard destination.canHide else { return }
        var set = hiddenTabs
        if set.contains(destination) { set.remove(destination) } else { set.insert(destination) }
        hiddenTabs = set
    }
}

/// App-wide text-size regulator, mapped onto SwiftUI Dynamic Type. Defaults to a
/// notch above the system standard so Mac text is easier to read out of the box.
enum AppTextSize: String, CaseIterable, Identifiable {
    case small, standard, large, larger, largest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "XS"
        case .standard: return "S"
        case .large: return "M"
        case .larger: return "XL"
        case .largest: return "XXL"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large      // SwiftUI's system default
        case .large: return .xLarge
        case .larger: return .xxLarge
        case .largest: return .xxxLarge
        }
    }
}

/// A configurable media-server quick link shown as its own navigation section.
enum MediaShortcut: String, CaseIterable, Identifiable {
    case plex, jellyfin
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plex: return "Plex"
        case .jellyfin: return "Jellyfin"
        }
    }

    /// Bundled brand logo (vector PDF imageset).
    var logoAssetName: String {
        switch self {
        case .plex: return "service-plex"
        case .jellyfin: return "service-jellyfin"
        }
    }

    /// Accent used on the landing card.
    var brandColorHex: UInt {
        switch self {
        case .plex: return 0xEBAF00
        case .jellyfin: return 0x00A4DC
        }
    }

    var defaultAppScheme: String {
        switch self {
        case .plex: return "plex://"
        case .jellyfin: return "jellyfin://"
        }
    }

    var destination: AppDestination {
        switch self {
        case .plex: return .plex
        case .jellyfin: return .jellyfin
        }
    }
}

/// What to do with a torrent that has been seeding longer than `maxSeedDays`.
enum SeedLimitAction: String, CaseIterable, Identifiable {
    /// Pause/stop the torrent but keep the data.
    case pause
    /// Remove the torrent from the client but keep the downloaded files.
    case remove
    /// Remove the torrent AND delete the downloaded files from disk.
    case removeAndDelete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pause: return "Pause"
        case .remove: return "Remove (keep files)"
        case .removeAndDelete: return "Remove & delete files"
        }
    }

    var symbol: String {
        switch self {
        case .pause: return "pause.circle"
        case .remove: return "minus.circle"
        case .removeAndDelete: return "trash"
        }
    }
}
