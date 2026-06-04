import SwiftUI
import NautilarrCore
import JellystatKit

/// A Jellystat dashboard: live sessions, per-user activity, library stats and
/// most-viewed / most-active leaderboards.
struct JellystatDetailView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings

    enum Segment: String, CaseIterable, Identifiable {
        case activity, users, libraries, stats
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .activity: return "Activity"
            case .users: return "Users"
            case .libraries: return "Libraries"
            case .stats: return "Stats"
            }
        }
        var systemImage: String {
            switch self {
            case .activity: return "play.tv"
            case .users: return "person.2"
            case .libraries: return "books.vertical"
            case .stats: return "chart.bar.xaxis"
            }
        }
    }

    @State private var segment: Segment = .activity
    @State private var sessions: [JellystatSession] = []
    @State private var users: [JellystatUserActivity] = []
    @State private var libraries: [JellystatLibraryCard] = []
    @State private var topMovies: [JellystatRanked] = []
    @State private var topSeries: [JellystatRanked] = []
    @State private var topUsers: [JellystatRanked] = []
    @State private var isLoading = false
    @State private var timeRange = 30
    @State private var query = ""
    /// The real error from the last activity fetch, surfaced instead of being
    /// silently swallowed so a failing stream lookup is diagnosable.
    @State private var activityError: String?

    private var client: JellystatClient? { instanceStore.jellystatClient(for: instance) }

    var body: some View {
        VStack(spacing: 0) {
            GlassSegmentedBar(tags: Segment.allCases, title: { $0.title }, systemImage: { $0.systemImage }, selection: $segment)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            filterBar
            content
        }
        .navigationTitle(instance.name)
        .appBackground(settings.background)
        .overlay { if isLoading && isCurrentEmpty { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: isLoading) { Task { await load() } }
            }
        }
        .task(id: segment) { await load() }
        .onChange(of: timeRange) { _, _ in if segment == .stats { Task { await load() } } }
        .refreshable { await load() }
    }

    private var isCurrentEmpty: Bool {
        switch segment {
        case .activity: return sessions.isEmpty
        case .users: return users.isEmpty
        case .libraries: return libraries.isEmpty
        case .stats: return topMovies.isEmpty && topSeries.isEmpty && topUsers.isEmpty
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        switch segment {
        case .stats:
            HStack {
                Spacer()
                Menu {
                    Picker("Range", selection: $timeRange) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                } label: {
                    Label("\(timeRange) days", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal).padding(.bottom, 6)
        case .users:
            SearchField(prompt: "Filter", text: $query)
                .padding(.horizontal).padding(.bottom, 6)
        default:
            EmptyView()
        }
    }

    private var filteredUsers: [JellystatUserActivity] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return users }
        return users.filter { ($0.userName ?? "").localizedStandardContains(q) }
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .activity: activityList
        case .users: usersList
        case .libraries: librariesList
        case .stats: statsList
        }
    }

    private var activityList: some View {
        List {
            if let activityError, sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't load sessions", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                    Text(activityError).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tintedCards()
            } else if sessions.isEmpty && !isLoading {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing is playing right now.").foregroundStyle(.secondary)
                    Text("If a stream is playing but isn't shown, your Jellystat may be using the Jellyfin WebSocket (Jellyfin 10.11+). Set JF_USE_WEBSOCKETS=false on the Jellystat server to fall back to polling.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .tintedCards()
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.displayTitle).font(.subheadline).lineLimit(2)
                        Spacer()
                        if session.isPaused { StatusBadge(text: "Paused", color: .orange) }
                    }
                    ProgressView(value: session.progress).tint(Theme.teal)
                    Text([session.userName, session.deviceName, session.client]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
            }
            .tintedCards()
        }
    }

    private var usersList: some View {
        List {
            if filteredUsers.isEmpty && !isLoading {
                Text("No user activity.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(filteredUsers) { user in
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.userName ?? "User").font(.subheadline)
                    HStack(spacing: 10) {
                        Label("\(user.totalPlays ?? 0)", systemImage: "play.fill")
                        Label(Format.duration(user.totalWatchTime), systemImage: "clock")
                        if let client = user.lastClient { Text(client) }
                    }
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
            }
            .tintedCards()
        }
    }

    private var librariesList: some View {
        List {
            if libraries.isEmpty && !isLoading {
                Text("No libraries.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(libraries) { library in
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.name ?? "Library").font(.subheadline)
                    HStack(spacing: 10) {
                        if let count = library.libraryCount { Label("\(count) items", systemImage: "square.stack") }
                        if let seasons = library.seasonCount, seasons > 0 { Text("\(seasons) seasons") }
                        if let episodes = library.episodeCount, episodes > 0 { Text("\(episodes) episodes") }
                        if let type = library.collectionType { Text(type.capitalized) }
                    }
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
            }
            .tintedCards()
        }
    }

    private var statsList: some View {
        List {
            if isCurrentEmpty && !isLoading {
                Text("No statistics for this period.").foregroundStyle(.secondary).tintedCards()
            }
            rankedSection("Most Watched Movies", rows: topMovies)
            rankedSection("Most Watched Series", rows: topSeries)
            rankedSection("Most Active Users", rows: topUsers)
        }
    }

    @ViewBuilder
    private func rankedSection(_ title: LocalizedStringKey, rows: [JellystatRanked]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name ?? "—").font(.subheadline).lineLimit(1)
                        Spacer()
                        if let plays = row.plays { Text("\(plays) plays").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .tintedCards()
        }
    }

    // MARK: - Data

    private func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        switch segment {
        case .activity:
            do {
                sessions = try await client.sessions()
                activityError = nil
            } catch {
                sessions = []
                activityError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        case .users:
            users = (try? await client.users()) ?? []
        case .libraries:
            libraries = (try? await client.libraryCards()) ?? []
        case .stats:
            async let movies = client.mostViewed(type: "Movie", days: timeRange)
            async let series = client.mostViewed(type: "Series", days: timeRange)
            async let active = client.mostActiveUsers(days: timeRange)
            topMovies = (try? await movies) ?? []
            topSeries = (try? await series) ?? []
            topUsers = (try? await active) ?? []
        }
    }
}
