import SwiftUI
import NautilarrCore

/// Upcoming releases as a day-grouped timeline or a month grid. Tapping any
/// title opens its library detail.
struct CalendarView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var model = CalendarViewModel()
    @AppStorage("calendarMonthView") private var monthView = false
    @Environment(\.horizontalSizeClass) private var hSize

    /// The month grid is only offered on roomy layouts (iPad/Mac); iPhone shows
    /// the list/timeline only.
    private var monthGridAvailable: Bool { hSize != .compact }
    private var showMonth: Bool { monthGridAvailable && monthView }

    var body: some View {
        VStack(spacing: 0) {
            if model.hasServices { calendarHeader }
            Group {
                if !model.hasServices {
                    ContentUnavailableLabel(
                        "No calendar",
                        systemImage: "calendar",
                        description: "Add a Sonarr or Radarr service in Settings to see upcoming releases."
                    )
                } else if showMonth {
                    CalendarMonthView(model: model)
                } else {
                    timeline
                }
            }
        }
        .navigationDestination(for: MediaEntry.self) { entry in detailView(for: entry) }
        .overlay { if model.isLoading && model.allEntries.isEmpty { ProgressView() } }
        .refreshable { await model.load(store: instanceStore) }
        .task { await model.load(store: instanceStore) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: model.isLoading) {
                    Task { await model.load(store: instanceStore) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nautilarrRefresh)) { _ in
            Task { await model.load(store: instanceStore) }
        }
    }

    /// In-content controls. Previously both the list/grid segmented control and
    /// the filter menu were `.primaryAction` toolbar items, which crowded and
    /// overlapped on iPhone. Laid out here with room to breathe.
    private var calendarHeader: some View {
        HStack(spacing: 12) {
            if monthGridAvailable {
                Picker("View", selection: $monthView) {
                    Image(systemName: "list.bullet").tag(false)
                    Image(systemName: "calendar").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }
            Spacer()
            filterMenu
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var timeline: some View {
        List {
            ForEach(model.days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        if let media = entry.mediaEntry {
                            NavigationLink(value: media) { CalendarRow(entry: entry) }
                        } else {
                            CalendarRow(entry: entry)
                        }
                    }
                } header: {
                    Text(day.date, format: .dateTime.weekday(.wide).month().day())
                }
                .tintedCards()
            }
            if model.days.isEmpty && !model.isLoading {
                Text("Nothing scheduled.").foregroundStyle(.secondary)
                    .tintedCards()
            }
        }
    }

    @ViewBuilder
    private func detailView(for entry: MediaEntry) -> some View {
        switch entry {
        case let .series(instance, series):
            SeriesDetailView(item: LibraryItem(instance: instance, series: series))
        case let .movie(instance, movie):
            MovieDetailView(instance: instance, movie: movie)
        case let .artist(instance, artist):
            ArtistDetailView(instance: instance, artist: artist)
        }
    }

    private var filterMenu: some View {
        Menu {
            if model.availableTypes.count > 1 {
                Picker("Type", selection: $model.typeFilter) {
                    Text("All Media").tag(ServiceType?.none)
                    ForEach(model.availableTypes) { type in
                        Text(type.displayName).tag(ServiceType?.some(type))
                    }
                }
            }
            Picker("Status", selection: $model.statusFilter) {
                Text("All Statuses").tag(CalendarViewModel.Status?.none)
                Text("Downloaded").tag(CalendarViewModel.Status?.some(.downloaded))
                Text("Missing").tag(CalendarViewModel.Status?.some(.missing))
                Text("Upcoming").tag(CalendarViewModel.Status?.some(.upcoming))
            }
            Toggle("Monitored only", isOn: $model.monitoredOnly)
            if isFiltering {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    model.typeFilter = nil; model.statusFilter = nil; model.monitoredOnly = false
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .font(.title3)
        }
    }

    private var isFiltering: Bool {
        model.typeFilter != nil || model.statusFilter != nil || model.monitoredOnly
    }
}

private struct CalendarRow: View {
    let entry: CalendarViewModel.Entry
    @EnvironmentObject private var instanceStore: InstanceStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            poster
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    StatusBadge(text: entry.status.label, color: entry.status.color)
                    if let date = entry.date {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(entry.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    ServiceIcon(type: entry.type, size: 14)
                    Text(entry.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = PosterURL.resolve(entry.posterURLString, instance: entry.instance) {
            AsyncCachedImage(
                url: url,
                headers: instanceStore.imageHeaders(for: entry.instance),
                allowSelfSignedHosts: entry.instance.allowSelfSignedCertificates
                    ? Set(entry.instance.candidateBaseURLs().compactMap { $0.host }) : []
            )
        } else {
            ZStack { Theme.backgroundGradient; Image(systemName: "film").foregroundStyle(.white.opacity(0.6)) }
        }
    }
}
