import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit

@MainActor
final class CalendarViewModel: ObservableObject {
    enum Status: Equatable { case downloaded, missing, upcoming }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date?
        let title: String
        let subtitle: String
        let type: ServiceType
        let instance: ServiceInstance
        let posterURLString: String?
        let status: Status
        let monitored: Bool
        /// The library item this entry maps to, so tapping it opens the detail.
        var mediaEntry: MediaEntry?
        /// Stable identity (type + instance + media id) used to de-duplicate
        /// entries that appear in more than one fetched window.
        let dedupKey: String
    }

    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let entries: [Entry]
    }

    @Published private(set) var allEntries: [Entry] = []
    @Published var isLoading = false
    @Published var hasServices = true

    // Filters (drive the computed `days`).
    @Published var typeFilter: ServiceType?
    @Published var statusFilter: Status?
    @Published var monitoredOnly = false

    /// All loaded entries keyed by `Entry.dedupKey` — the source of truth behind
    /// `allEntries`. Fetching more windows merges into this so navigating the
    /// month grid accumulates data instead of being capped at a fixed window.
    private var entriesByKey: [String: Entry] = [:]
    /// Month-start anchors already fetched outside the default window, so the
    /// grid doesn't refetch a month every time it revisits it.
    private var loadedMonths: Set<Date> = []

    private var cal: Calendar { Calendar.current }
    /// Days fetched before / after "now" for the default upcoming window.
    private let defaultLookbehindDays = 7
    private let defaultLookaheadDays = 90

    /// Service types present in the loaded window, for the filter menu.
    var availableTypes: [ServiceType] {
        Array(Set(allEntries.map(\.type))).sorted { $0.rawValue < $1.rawValue }
    }

    /// Entries after the filter menu is applied (regardless of grouping).
    var filteredEntries: [Entry] {
        allEntries.filter { entry in
            (typeFilter == nil || entry.type == typeFilter)
            && (statusFilter == nil || entry.status == statusFilter)
            && (!monitoredOnly || entry.monitored)
        }
    }

    /// Filtered, day-grouped entries shown in the timeline.
    var days: [Day] {
        let grouped = Dictionary(grouping: filteredEntries.filter { $0.date != nil }) {
            Calendar.current.startOfDay(for: $0.date!)
        }
        return grouped.keys.sorted().map { key in
            Day(date: key, entries: grouped[key]!.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
        }
    }

    /// Filtered entries grouped by the day they occur on (for the month grid).
    var entriesByDay: [Date: [Entry]] {
        Dictionary(grouping: filteredEntries.filter { $0.date != nil }) {
            Calendar.current.startOfDay(for: $0.date!)
        }
    }

    /// Initial load and refresh: rebuild the default upcoming window
    /// (`-defaultLookbehindDays … +defaultLookaheadDays`) and re-fetch any months
    /// the user navigated to, so a pull-to-refresh keeps far months current too.
    func load(store: InstanceStore) async {
        let sonarr = store.instances(ofType: .sonarr)
        let radarr = store.instances(ofType: .radarr)
        hasServices = !(sonarr.isEmpty && radarr.isEmpty)
        guard hasServices else {
            allEntries = []; entriesByKey = [:]; loadedMonths = []; return
        }

        if allEntries.isEmpty { isLoading = true }
        defer { isLoading = false }

        let now = Date()
        let start = cal.date(byAdding: .day, value: -defaultLookbehindDays, to: now) ?? now
        // Look ~3 months ahead so genuinely-future releases appear, not just the week.
        let end = cal.date(byAdding: .day, value: defaultLookaheadDays, to: now) ?? now

        entriesByKey = [:]
        await fetchAndMerge(start: start, end: end, store: store)
        // Re-fetch any far months the user navigated to so they survive a refresh.
        for anchor in loadedMonths {
            let window = monthWindow(for: anchor)
            await fetchAndMerge(start: window.start, end: window.end, store: store)
        }
        publish()
    }

    /// Load the window around a month shown in the grid, merging it into the
    /// accumulated entries. Months already covered by the default window or a
    /// previous fetch are a no-op, so navigating forward / back keeps loading
    /// data with no fixed cap.
    func loadMonth(_ month: Date, store: InstanceStore) async {
        guard hasServices else { return }
        let anchor = cal.dateInterval(of: .month, for: month)?.start ?? month
        guard !isWithinDefaultWindow(anchor), !loadedMonths.contains(anchor) else { return }

        loadedMonths.insert(anchor)
        isLoading = true
        defer { isLoading = false }
        let window = monthWindow(for: anchor)
        await fetchAndMerge(start: window.start, end: window.end, store: store)
        publish()
    }

    /// Fetch the calendar for every Sonarr/Radarr instance in `[start, end]` and
    /// merge the results into `entriesByKey`, keyed by a stable id so overlapping
    /// windows never duplicate an entry.
    private func fetchAndMerge(start: Date, end: Date, store: InstanceStore) async {
        let now = Date()
        for instance in store.instances(ofType: .sonarr) {
            guard let client = store.sonarrClient(for: instance) else { continue }
            // `unmonitored: true` so the calendar isn't limited to monitored items —
            // that omission is why upcoming releases could look missing.
            if let episodes = try? await client.calendar(start: start, end: end, unmonitored: true) {
                for ep in episodes {
                    let status: Status = ep.hasFile == true ? .downloaded
                        : ((ep.airDateUtc ?? .distantFuture) < now ? .missing : .upcoming)
                    let entry = Entry(date: ep.airDateUtc,
                                      title: ep.series?.title ?? "Series",
                                      subtitle: "\(ep.seasonEpisodeCode) · \(ep.title ?? "")",
                                      type: .sonarr, instance: instance,
                                      posterURLString: ep.series?.imageURL(coverType: "poster"),
                                      status: status, monitored: ep.monitored ?? false,
                                      mediaEntry: ep.series.map { .series(instance: instance, series: $0) },
                                      dedupKey: "sonarr-\(instance.id)-\(ep.id)")
                    entriesByKey[entry.dedupKey] = entry
                }
            }
        }
        for instance in store.instances(ofType: .radarr) {
            guard let client = store.radarrClient(for: instance) else { continue }
            if let movies = try? await client.calendar(start: start, end: end, unmonitored: true) {
                for movie in movies {
                    let date = movie.digitalRelease ?? movie.physicalRelease ?? movie.inCinemas
                    let status: Status = movie.hasFile == true ? .downloaded
                        : (movie.isAvailable == true ? .missing : .upcoming)
                    let entry = Entry(date: date, title: movie.title, subtitle: "Movie",
                                      type: .radarr, instance: instance,
                                      posterURLString: movie.imageURL(coverType: "poster"),
                                      status: status, monitored: movie.monitored ?? false,
                                      mediaEntry: .movie(instance: instance, movie: movie),
                                      dedupKey: "radarr-\(instance.id)-\(movie.id)")
                    entriesByKey[entry.dedupKey] = entry
                }
            }
        }
    }

    /// `[start, end]` covering a month plus a week of spill-over each side, so the
    /// grid's leading / trailing days from adjacent months also have data.
    private func monthWindow(for monthStart: Date) -> (start: Date, end: Date) {
        let start = cal.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let end = cal.date(byAdding: .day, value: 7, to: monthEnd) ?? monthEnd
        return (start, end)
    }

    /// Whether a displayed month already lies fully inside the default upcoming
    /// window, so the grid doesn't trigger a redundant fetch for it.
    private func isWithinDefaultWindow(_ monthStart: Date) -> Bool {
        let now = Date()
        guard let defaultStart = cal.date(byAdding: .day, value: -defaultLookbehindDays, to: now),
              let defaultEnd = cal.date(byAdding: .day, value: defaultLookaheadDays, to: now),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return false }
        return monthStart >= cal.startOfDay(for: defaultStart) && monthEnd <= defaultEnd
    }

    /// Republish `allEntries` (date-sorted) from the keyed store.
    private func publish() {
        allEntries = entriesByKey.values.sorted {
            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
    }
}

extension CalendarViewModel.Status {
    var label: String {
        switch self {
        case .downloaded: return "Downloaded"
        case .missing: return "Missing"
        case .upcoming: return "Upcoming"
        }
    }
    var color: Color {
        switch self {
        case .downloaded: return .green
        case .missing: return .orange
        case .upcoming: return .secondary
        }
    }
}
