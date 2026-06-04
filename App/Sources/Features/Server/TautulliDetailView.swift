import SwiftUI
import NautilarrCore
import TautulliKit

/// A full Tautulli dashboard: live activity (with the ability to terminate a
/// stream), watch history, home statistics, users and libraries.
struct TautulliDetailView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings

    enum Segment: String, CaseIterable, Identifiable {
        case activity, history, stats, users, libraries
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .activity: return "Activity"
            case .history: return "History"
            case .stats: return "Stats"
            case .users: return "Users"
            case .libraries: return "Libraries"
            }
        }
        var systemImage: String {
            switch self {
            case .activity: return "play.tv"
            case .history: return "clock.arrow.circlepath"
            case .stats: return "chart.bar.xaxis"
            case .users: return "person.2"
            case .libraries: return "books.vertical"
            }
        }
    }

    @State private var segment: Segment = .activity
    @State private var sessions: [TautulliSession] = []
    @State private var history: [TautulliHistoryRecord] = []
    @State private var homeStats: [TautulliHomeStat] = []
    @State private var users: [TautulliUserRow] = []
    @State private var libraries: [TautulliLibraryRow] = []
    @State private var isLoading = false
    @State private var status: String?
    @State private var terminateTarget: TautulliSession?
    /// The real error from the last activity fetch, surfaced instead of being
    /// silently swallowed so a failing stream lookup is diagnosable.
    @State private var activityError: String?
    // Filters
    @State private var timeRange = 30          // Stats window in days
    @State private var query = ""              // History/Users text filter

    private var client: TautulliClient? { instanceStore.tautulliClient(for: instance) }

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
        .overlay(alignment: .bottom) { Toast(message: status) { status = nil } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: isLoading) { Task { await load() } }
            }
        }
        .task(id: segment) { await load() }
        .onChange(of: timeRange) { _, _ in if segment == .stats { Task { await load() } } }
        .refreshable { await load() }
        .confirmationDialog(
            "Terminate this stream?",
            isPresented: Binding(get: { terminateTarget != nil }, set: { if !$0 { terminateTarget = nil } }),
            presenting: terminateTarget
        ) { session in
            Button("Terminate", role: .destructive) { Task { await terminate(session) } }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text(session.displayTitle)
        }
    }

    private var isCurrentEmpty: Bool {
        switch segment {
        case .activity: return sessions.isEmpty
        case .history: return history.isEmpty
        case .stats: return homeStats.isEmpty
        case .users: return users.isEmpty
        case .libraries: return libraries.isEmpty
        }
    }

    /// Per-tab filter controls: a time-range menu on Stats, a search field on the
    /// History and Users lists.
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
        case .history, .users:
            SearchField(prompt: "Filter", text: $query)
                .padding(.horizontal).padding(.bottom, 6)
        default:
            EmptyView()
        }
    }

    private var filteredHistory: [TautulliHistoryRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return history }
        return history.filter {
            $0.displayTitle.localizedStandardContains(q)
                || ($0.friendlyName ?? $0.user ?? "").localizedStandardContains(q)
        }
    }

    private var filteredUsers: [TautulliUserRow] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return users }
        return users.filter { ($0.friendlyName ?? "").localizedStandardContains(q) }
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .activity: activityList
        case .history: historyList
        case .stats: statsList
        case .users: usersList
        case .libraries: librariesList
        }
    }

    // MARK: - Activity

    private var activityList: some View {
        List {
            if let activityError, sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't load activity", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                    Text(activityError).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tintedCards()
            } else if sessions.isEmpty && !isLoading {
                Text("Nothing is playing right now.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.displayTitle).font(.subheadline).lineLimit(2)
                        Spacer()
                        if session.isTranscoding { StatusBadge(text: "Transcode", color: .orange) }
                    }
                    ProgressView(value: session.progress).tint(Theme.teal)
                    HStack(spacing: 6) {
                        Text([session.user, session.player, session.state?.capitalized]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            terminateTarget = session
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(session.sessionKey == nil)
                    }
                }
                .padding(.vertical, 2)
            }
            .tintedCards()
        }
    }

    // MARK: - History

    private var historyList: some View {
        List {
            if filteredHistory.isEmpty && !isLoading {
                Text("No watch history yet.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(filteredHistory) { record in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(record.displayTitle).font(.subheadline).lineLimit(1)
                        Spacer()
                        if record.isTranscoding { StatusBadge(text: "Transcode", color: .orange) }
                    }
                    HStack(spacing: 6) {
                        Text([record.friendlyName ?? record.user, record.player].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if let date = record.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if let pct = record.percentComplete, pct > 0 {
                        ProgressView(value: Double(min(100, pct)) / 100).tint(Theme.teal)
                    }
                }
                .padding(.vertical, 2)
            }
            .tintedCards()
        }
    }

    // MARK: - Home stats

    private var statsList: some View {
        List {
            if homeStats.allSatisfy({ $0.rows.isEmpty }) && !isLoading {
                Text("No statistics for this period.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(homeStats) { stat in
                if !stat.rows.isEmpty {
                    Section(LocalizedStringKey(stat.statTitle ?? "Statistic")) {
                        ForEach(stat.rows.prefix(5)) { row in
                            HStack {
                                Text(row.label).font(.subheadline).lineLimit(1)
                                Spacer()
                                if let plays = row.totalPlays, plays > 0 {
                                    Text("\(plays) plays").font(.caption).foregroundStyle(.secondary)
                                } else if let dur = row.totalDuration, dur > 0 {
                                    Text(Format.duration(dur)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .tintedCards()
                }
            }
        }
    }

    // MARK: - Users

    private var usersList: some View {
        List {
            if filteredUsers.isEmpty && !isLoading {
                Text("No users.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(filteredUsers) { user in
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.friendlyName ?? "User").font(.subheadline)
                    HStack(spacing: 10) {
                        Label("\(user.plays ?? 0)", systemImage: "play.fill")
                        Label(Format.duration(user.duration), systemImage: "clock")
                        if let date = user.lastSeenDate {
                            Label { Text(date, format: .relative(presentation: .named)) } icon: { Image(systemName: "eye") }
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .tintedCards()
        }
    }

    // MARK: - Libraries

    private var librariesList: some View {
        List {
            if libraries.isEmpty && !isLoading {
                Text("No libraries.").foregroundStyle(.secondary).tintedCards()
            }
            ForEach(libraries) { library in
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.sectionName ?? "Library").font(.subheadline)
                    HStack(spacing: 10) {
                        if let count = library.count { Label("\(count) items", systemImage: "square.stack") }
                        if let plays = library.plays { Label("\(plays) plays", systemImage: "play.fill") }
                        if let type = library.sectionType { Text(type.capitalized) }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
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
                sessions = try await client.activity().sessions
                activityError = nil
            } catch {
                sessions = []
                activityError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        case .history:
            history = ((try? await client.history(length: 50))?.data) ?? []
        case .stats:
            homeStats = (try? await client.homeStats(timeRange: timeRange)) ?? []
        case .users:
            users = ((try? await client.usersTable())?.data) ?? []
        case .libraries:
            libraries = ((try? await client.librariesTable())?.data) ?? []
        }
    }

    private func terminate(_ session: TautulliSession) async {
        guard let client, let key = session.sessionKey else { return }
        do {
            try await client.terminateSession(sessionKey: key, message: "Your stream was stopped by the administrator.")
            status = "Stream terminated."
            await load()
        } catch {
            status = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
