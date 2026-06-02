import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit
#if canImport(UIKit)
import UIKit
#endif

/// Global search: filters your existing library across every configured Sonarr,
/// Radarr and Lidarr instance as you type, and — on submit — looks up the
/// metadata providers so you can add new titles, choosing which service to add
/// them to when more than one is configured.
struct GlobalSearchView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var library = LibraryViewModel()

    @State private var seriesResults: [SonarrSeries] = []
    @State private var movieResults: [RadarrMovie] = []
    @State private var artistResults: [LidarrArtist] = []
    @State private var isSearchingProviders = false
    @State private var didSearchProviders = false

    @State private var pendingSeries: SeriesAdd?
    @State private var pendingMovie: MovieAdd?
    @State private var pendingArtist: ArtistAdd?
    /// State-driven navigation for library matches. Tapping a result dismisses
    /// the keyboard first and sets this — a `NavigationLink` in the live-filtered
    /// list was popping straight back as the keyboard dismissal re-laid-out the
    /// list mid-push.
    @State private var openedEntry: MediaEntry?

    private var sonarr: [ServiceInstance] { instanceStore.instances(ofType: .sonarr) }
    private var radarr: [ServiceInstance] { instanceStore.instances(ofType: .radarr) }
    private var lidarr: [ServiceInstance] { instanceStore.instances(ofType: .lidarr) }
    private var hasMediaServices: Bool { !(sonarr.isEmpty && radarr.isEmpty && lidarr.isEmpty) }
    private var term: String { library.searchText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group {
            if !hasMediaServices {
                ContentUnavailableLabel(
                    "Nothing to search",
                    systemImage: "magnifyingglass",
                    description: "Add a Sonarr, Radarr or Lidarr service in Settings to search your library and add titles."
                )
            } else {
                VStack(spacing: 0) {
                    SearchField(prompt: "Search library or add new", text: $library.searchText) {
                        Task { await searchProviders() }
                    }
                    .padding([.horizontal, .top])
                    .padding(.bottom, 8)
                    List {
                        if term.isEmpty {
                            Section {
                                Text("Search your library, or press return to find new titles to add.")
                                    .foregroundStyle(.secondary).font(.subheadline)
                            }
                        } else {
                            librarySection
                            addSection
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $openedEntry) { entry in destination(for: entry) }
        .onChange(of: library.searchText) { _, _ in
            didSearchProviders = false
            seriesResults = []; movieResults = []; artistResults = []
        }
        .overlay { if isSearchingProviders { ProgressView() } }
        .task { await library.load(store: instanceStore) }
        .onReceive(NotificationCenter.default.publisher(for: .nautilarrRefresh)) { _ in
            Task { await library.load(store: instanceStore) }
        }
        .sheet(item: $pendingSeries) { add in
            AddSeriesOptionsView(instance: add.instance, lookup: add.series) { Task { await library.load(store: instanceStore) } }
        }
        .sheet(item: $pendingMovie) { add in
            AddMovieOptionsView(instance: add.instance, lookup: add.movie) { Task { await library.load(store: instanceStore) } }
        }
        .sheet(item: $pendingArtist) { add in
            AddArtistOptionsView(instance: add.instance, lookup: add.artist) { Task { await library.load(store: instanceStore) } }
        }
    }

    // MARK: - Library matches

    @ViewBuilder
    private var librarySection: some View {
        let matches = library.filtered
        Section("In your library (\(matches.count))") {
            if matches.isEmpty {
                Text("No matching items in your library.").foregroundStyle(.secondary).font(.subheadline)
            }
            ForEach(matches) { entry in
                Button {
                    dismissKeyboard()
                    openedEntry = entry
                } label: {
                    LibrarySearchRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    // MARK: - Add new

    @ViewBuilder
    private var addSection: some View {
        Section("Add to library") {
            if !didSearchProviders && !isSearchingProviders {
                Button { Task { await searchProviders() } } label: {
                    Label("Search providers for “\(term)”", systemImage: "sparkle.magnifyingglass")
                }
            }
            ForEach(seriesResults) { series in
                addRow(title: series.title, subtitle: series.year.map(String.init), kind: .series, instances: sonarr) { inst in
                    pendingSeries = SeriesAdd(instance: inst, series: series)
                }
            }
            ForEach(movieResults) { movie in
                addRow(title: movie.title, subtitle: movie.year.map(String.init), kind: .movie, instances: radarr) { inst in
                    pendingMovie = MovieAdd(instance: inst, movie: movie)
                }
            }
            ForEach(artistResults) { artist in
                addRow(title: artist.artistName, subtitle: nil, kind: .artist, instances: lidarr) { inst in
                    pendingArtist = ArtistAdd(instance: inst, artist: artist)
                }
            }
            if didSearchProviders && !isSearchingProviders
                && seriesResults.isEmpty && movieResults.isEmpty && artistResults.isEmpty {
                Text("No new titles found to add.").foregroundStyle(.secondary).font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func addRow(title: String, subtitle: String?, kind: MediaKind, instances: [ServiceInstance], add: @escaping (ServiceInstance) -> Void) -> some View {
        HStack {
            Image(systemName: kind.symbol).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if instances.count <= 1 {
                Button { if let inst = instances.first { add(inst) } } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(instances.isEmpty)
            } else {
                Menu {
                    ForEach(instances) { inst in Button(inst.name) { add(inst) } }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func destination(for entry: MediaEntry) -> some View {
        switch entry {
        case let .series(instance, series):
            SeriesDetailView(item: LibraryItem(instance: instance, series: series))
        case let .movie(instance, movie):
            MovieDetailView(instance: instance, movie: movie)
        case let .artist(instance, artist):
            ArtistDetailView(instance: instance, artist: artist)
        }
    }

    private func searchProviders() async {
        let t = term
        guard !t.isEmpty else { return }
        isSearchingProviders = true
        didSearchProviders = true
        defer { isSearchingProviders = false }
        // Metadata lookups are provider-wide, so a single instance per kind is
        // enough to fetch results; the user picks the add target per result.
        if let inst = sonarr.first, let c = instanceStore.sonarrClient(for: inst) {
            seriesResults = (try? await c.lookupSeries(term: t)) ?? []
        }
        if let inst = radarr.first, let c = instanceStore.radarrClient(for: inst) {
            movieResults = (try? await c.lookupMovies(term: t)) ?? []
        }
        if let inst = lidarr.first, let c = instanceStore.lidarrClient(for: inst) {
            artistResults = (try? await c.lookupArtists(term: t)) ?? []
        }
    }
}

// MARK: - Add targets (instance + looked-up item)

private struct SeriesAdd: Identifiable { let id = UUID(); let instance: ServiceInstance; let series: SonarrSeries }
private struct MovieAdd: Identifiable { let id = UUID(); let instance: ServiceInstance; let movie: RadarrMovie }
private struct ArtistAdd: Identifiable { let id = UUID(); let instance: ServiceInstance; let artist: LidarrArtist }

// MARK: - Library match row

private struct LibrarySearchRow: View {
    let entry: MediaEntry

    var body: some View {
        HStack(spacing: 10) {
            ServiceIcon(type: entry.instance.type, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.subheadline).lineLimit(1)
                Text(entry.subtitle.isEmpty ? entry.detail : entry.subtitle)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if entry.isMonitored {
                Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.teal)
            }
        }
    }
}
