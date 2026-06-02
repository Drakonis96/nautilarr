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
    @State private var selection: CompactTab = .destination(.home)

    /// iOS only shows five tab items before folding the rest into its OWN
    /// "More" navigation controller. That overflow controller double-stacks
    /// navigation bars (the dreaded *second* back arrow) and stops our pushed
    /// screens from re-rendering live (e.g. a background-colour change only
    /// taking effect after toggling light/dark). We sidestep it completely by
    /// never handing `TabView` more than five children: the first four
    /// destinations stay as direct tabs and everything else lives under a
    /// custom "More" tab that uses our own `NavigationStack`.
    private var directTabs: [AppDestination] {
        let all = settings.visibleTabOrder
        return all.count > 5 ? Array(all.prefix(4)) : all
    }

    private var overflow: [AppDestination] {
        let all = settings.visibleTabOrder
        return all.count > 5 ? Array(all.dropFirst(4)) : []
    }

    private var overflowBadge: Int {
        overflow.contains(where: \.showsActivityBadge) ? environment.activeDownloadCount : 0
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
                .tabItem { destination.navLabel }
                .badge(destination.showsActivityBadge ? environment.activeDownloadCount : 0)
                .tag(CompactTab.destination(destination))
            }
            if !overflow.isEmpty {
                NavigationStack {
                    MoreView(destinations: overflow)
                        .appBackground(settings.background)
                        .themedBars(settings.background)
                }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .badge(overflowBadge)
                .tag(CompactTab.more)
            }
        }
        // If hiding/reordering tabs (from the More list) drops the selected tab,
        // fall back to Home so the screen never goes blank.
        .onChange(of: settings.visibleTabOrder) { _, _ in
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
                NavigationLink {
                    destination.rootView
                        .navigationTitle(LocalizedStringKey(destination.title))
                        .appBackground(settings.background)
                } label: {
                    destination.navLabel
                        .badge(destination.showsActivityBadge ? environment.activeDownloadCount : 0)
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
    @State private var selection: AppDestination? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showAbout = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    ForEach(settings.visibleTabOrder) { destination in
                        NavigationLink(value: destination) {
                            destination.navLabel
                                .badge(destination.showsActivityBadge ? environment.activeDownloadCount : 0)
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
            .appBackground(settings.background)
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
        case .requests: RequestsView()
        case .indexers: IndexersView()
        case .subtitles: SubtitlesView()
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
