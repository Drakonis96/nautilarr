import SwiftUI

/// Adaptive container: a sidebar + detail split on iPad and Mac (regular width),
/// and a tab bar on iPhone (compact width). Respects the user's tab ordering.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            CompactRootView()
        } else {
            SidebarRootView()
        }
    }
}

// MARK: - iPhone: tab bar

/// Selection for the compact tab bar — either a real destination or our own
/// "More" tab.
private enum CompactTab: Hashable {
    case destination(AppDestination)
    case more
}

private struct CompactRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var selection: CompactTab = .destination(.home)
    /// Programmatic navigation path for the "More" tab, so the quick-access fan
    /// can push an overflow section directly.
    @State private var morePath: [AppDestination] = []

    /// Visible destinations, minus service-specific sections that have no
    /// configured instance (so Tautulli/SSH/etc. only appear once added).
    private var visible: [AppDestination] {
        settings.visibleTabOrder.filter { $0.isConfigured(in: instanceStore) }
    }

    /// The next sections after the bottom tab bar — surfaced by the quick-access
    /// fan for one-tap reach.
    private var quickDestinations: [AppDestination] {
        let beyond = Array(visible.dropFirst(4))
        return Array((beyond.isEmpty ? Array(visible.dropFirst(1)) : beyond).prefix(3))
    }

    /// Jump to a section from the quick-access fan (switch tab, or push it in
    /// the More stack if it lives in the overflow).
    private func quickNav(_ dest: AppDestination) {
        if directTabs.contains(dest) {
            morePath = []
            selection = .destination(dest)
        } else if overflow.contains(dest) {
            morePath = [dest]
            selection = .more
        } else {
            selection = .destination(.home)
        }
    }

    /// iOS only shows five tab items before folding the rest into its OWN
    /// "More" navigation controller. That overflow controller double-stacks
    /// navigation bars (the dreaded *second* back arrow) and stops our pushed
    /// screens from re-rendering live (e.g. a background-colour change only
    /// taking effect after toggling light/dark). We sidestep it completely by
    /// never handing `TabView` more than five children: the first four
    /// destinations stay as direct tabs and everything else lives under a
    /// custom "More" tab that uses our own `NavigationStack`.
    private var directTabs: [AppDestination] {
        let all = visible
        return all.count > 5 ? Array(all.prefix(4)) : all
    }

    private var overflow: [AppDestination] {
        let all = visible
        return all.count > 5 ? Array(all.dropFirst(4)) : []
    }

    private var overflowBadge: Int {
        overflow.reduce(0) { $0 + $1.badgeCount(in: environment) }
    }

    /// Whether the current selection still maps to a visible tab.
    private var selectionIsValid: Bool {
        switch selection {
        case .more: return !overflow.isEmpty
        case let .destination(d): return directTabs.contains(d)
        }
    }

    var body: some View {
        // Driven by the user's saved tab order so reordering in Appearance takes
        // effect immediately.
        TabView(selection: $selection) {
            ForEach(directTabs) { destination in
                NavigationStack {
                    destination.rootView
                        .navigationTitle(LocalizedStringKey(destination.title))
                        .appBackground(settings.background)
                        .themedBars(settings.background)
                }
                // Re-localize the whole tab (incl. nav titles and any pushed
                // screens) the instant the language changes.
                .id(settings.localeIdentifier)
                .floatingButtons(scrollToTop: settings.scrollToTopEnabled,
                                 quickNav: settings.quickNavEnabled,
                                 quickDestinations: quickDestinations,
                                 onSelect: quickNav)
                .tabItem { destination.navLabel }
                .badge(destination.badgeCount(in: environment))
                .tag(CompactTab.destination(destination))
            }
            if !overflow.isEmpty {
                NavigationStack(path: $morePath) {
                    MoreView(destinations: overflow)
                        .appBackground(settings.background)
                        .themedBars(settings.background)
                        .navigationDestination(for: AppDestination.self) { dest in
                            dest.rootView
                                .navigationTitle(LocalizedStringKey(dest.title))
                                .appBackground(settings.background)
                        }
                }
                .id(settings.localeIdentifier)
                .floatingButtons(scrollToTop: settings.scrollToTopEnabled,
                                 quickNav: settings.quickNavEnabled,
                                 quickDestinations: quickDestinations,
                                 onSelect: quickNav)
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .badge(overflowBadge)
                .tag(CompactTab.more)
            }
        }
        // If hiding/reordering tabs (or removing a service) drops the selected
        // tab, fall back to Home so the screen never goes blank.
        .onChange(of: visible) { _, _ in
            if !selectionIsValid { selection = .destination(.home) }
        }
    }
}

/// Our own "More" list (replaces iOS's system overflow tab). A single
/// `NavigationStack` so pushed screens show exactly one back arrow and update
/// live with the rest of the app.
private struct MoreView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    let destinations: [AppDestination]

    var body: some View {
        List {
            ForEach(destinations) { destination in
                NavigationLink(value: destination) {
                    destination.navLabel
                        .badge(destination.badgeCount(in: environment))
                }
            }
            .tintedCards()
        }
        .navigationTitle("More")
    }
}

// MARK: - iPad / Mac: sidebar + detail

private struct SidebarRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var selection: AppDestination? = .home

    private var visible: [AppDestination] {
        settings.visibleTabOrder.filter { $0.isConfigured(in: instanceStore) }
    }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showAbout = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    ForEach(visible) { destination in
                        NavigationLink(value: destination) {
                            destination.navLabel
                                .badge(destination.badgeCount(in: environment))
                        }
                    }
                } header: {
                    brandHeader
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(settings.background.isCustom ? .hidden : .automatic)
            .background(settings.background.backgroundView)
        } detail: {
            NavigationStack {
                if let selection {
                    selection.rootView
                        .navigationTitle(LocalizedStringKey(selection.title))
                } else {
                    ContentUnavailableLabel(
                        "Select a section",
                        systemImage: "sailboat",
                        description: "Choose a destination from the sidebar."
                    )
                }
            }
            .id(settings.localeIdentifier)
            .appBackground(settings.background)
            .floatingButtons(scrollToTop: settings.scrollToTopEnabled,
                             quickNav: settings.quickNavEnabled,
                             quickDestinations: Array(visible.dropFirst(4).prefix(3)),
                             onSelect: { selection = $0 })
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showAbout) { AboutSplashView() }
    }

    /// Big, prominent brand mark. Tapping the logo or wordmark opens the animated
    /// About splash.
    private var brandHeader: some View {
        Button {
            showAbout = true
        } label: {
            HStack(spacing: 14) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(color: Theme.teal.opacity(0.45), radius: 10, y: 3)
                VStack(alignment: .leading, spacing: 0) {
                    Text("nautilARR")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundStyle(.primary)
                    Text("Self-hosted media")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .padding(.vertical, 10)
    }
}

// MARK: - Destination → view

extension AppDestination {
    @ViewBuilder var rootView: some View {
        switch self {
        case .home: HomeView()
        case .plex: ShortcutLandingView(kind: .plex)
        case .jellyfin: ShortcutLandingView(kind: .jellyfin)
        case .library: LibraryView()
        case .calendar: CalendarView()
        case .search: GlobalSearchView()
        case .downloads: DownloadsView()
        case .inbox: InboxView()
        case .requests: RequestsView()
        case .indexers: IndexersView()
        case .subtitles: SubtitlesView()
        case .tautulli:
            ServiceSection(type: .tautulli, emptyTitle: "No Tautulli",
                           emptyDescription: "Add a Tautulli service in Settings to see playback statistics.") {
                TautulliDetailView(instance: $0)
            }
        case .jellystat:
            ServiceSection(type: .jellystat, emptyTitle: "No Jellystat",
                           emptyDescription: "Add a Jellystat service in Settings to see playback statistics.") {
                JellystatDetailView(instance: $0)
            }
        case .unraid:
            ServiceSection(type: .unraid, emptyTitle: "No Unraid",
                           emptyDescription: "Add an Unraid service in Settings to see system, array and Docker status.") {
                UnraidDetailView(instance: $0)
            }
        case .ssh:
            ServiceSection(type: .ssh, emptyTitle: "No SSH services",
                           emptyDescription: "Add an SSH service in Settings for a terminal, host stats and a file browser.") {
                SSHDetailView(instance: $0)
            }
        case .server: ServerView()
        case .settings: SettingsView()
        }
    }
}

/// iOS 16-compatible stand-in for `ContentUnavailableView` (iOS 17+).
struct ContentUnavailableLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    init(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: 360)
    }
}
