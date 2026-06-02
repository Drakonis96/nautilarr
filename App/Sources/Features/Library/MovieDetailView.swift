import SwiftUI
import NautilarrCore
import RadarrKit

@MainActor
final class MovieDetailViewModel: ObservableObject {
    @Published var statusMessage: String?
    @Published var didDelete = false
    @Published var releases: [RadarrRelease] = []
    @Published var isSearching = false
    @Published var monitored: Bool

    private let instance: ServiceInstance
    private let movie: RadarrMovie
    private weak var store: InstanceStore?
    private var client: RadarrClient? { store?.radarrClient(for: instance) }

    init(instance: ServiceInstance, movie: RadarrMovie) {
        self.instance = instance
        self.movie = movie
        self.monitored = movie.monitored ?? false
    }
    func configure(store: InstanceStore) { self.store = store }

    func setMonitored(_ value: Bool) async {
        monitored = value
        guard let client else { return }
        do {
            try await client.editMovies(ids: [movie.id], monitored: value)
            statusMessage = value ? "Now monitoring." : "No longer monitoring."
        } catch {
            monitored = !value
            statusMessage = describe(error)
        }
    }

    func automaticSearch() async {
        await run(.movieSearch(movieId: movie.id), success: "Searching for this movie…")
    }
    func refresh() async {
        await run(.refreshMovie(movieId: movie.id), success: "Refreshing movie…")
    }
    private func run(_ command: RadarrCommandRequest, success: String) async {
        guard let client else { return }
        do { _ = try await client.runCommand(command); statusMessage = success }
        catch { statusMessage = describe(error) }
    }

    func delete(deleteFiles: Bool) async {
        guard let client else { return }
        do { try await client.deleteMovie(id: movie.id, deleteFiles: deleteFiles); didDelete = true }
        catch { statusMessage = describe(error) }
    }

    func loadReleases() async {
        guard let client else { return }
        isSearching = true
        defer { isSearching = false }
        releases = ((try? await client.releases(movieId: movie.id)) ?? [])
            .sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
    }

    func grab(_ release: RadarrRelease) async {
        guard let client else { return }
        do { try await client.grab(release); statusMessage = "Sent to download client." }
        catch { statusMessage = describe(error) }
    }

    private func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}

/// Movie detail: artwork, overview, availability and actions (search, refresh,
/// delete, interactive search → grab).
struct MovieDetailView: View {
    let instance: ServiceInstance
    let movie: RadarrMovie
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MovieDetailViewModel
    @State private var showDeleteConfirm = false
    @State private var showReleases = false
    @State private var editing: MediaEntry?

    init(instance: ServiceInstance, movie: RadarrMovie) {
        self.instance = instance
        self.movie = movie
        _model = StateObject(wrappedValue: MovieDetailViewModel(instance: instance, movie: movie))
    }

    var body: some View {
        List {
            Section { MediaDetailHeader(data: headerData) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            if let overview = movie.overview, !overview.isEmpty {
                Section("Overview") { Text(overview).font(.subheadline) }
                    .tintedCards()
            }

            // Details sits right under the synopsis (the cast strip used to wedge
            // between them, pushing details far down the page).
            detailsSection
                .tintedCards()

            if movie.hasFile == true, let file = movie.movieFile, let m = movieFileMeta(file), m.hasAny {
                Section("File") { FileInfoRows(meta: m) }
                    .tintedCards()
            }

            // Cast only when a requests service (Overseerr/Jellyseerr) is set up —
            // otherwise the section is always empty and just leaves a gap.
            if hasCastSource {
                Section { MediaCastStrip(mediaType: "movie", tmdbId: movie.tmdbId, title: movie.title, year: movie.year) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Monitored", isOn: Binding(
                    get: { model.monitored },
                    set: { value in Task { await model.setMonitored(value) } }
                ))
                Button { editing = .movie(instance: instance, movie: movie) } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                Button { Task { await model.automaticSearch() } } label: {
                    Label("Automatic Search", systemImage: "magnifyingglass")
                }
                Button { showReleases = true } label: {
                    Label("Interactive Search", systemImage: "list.bullet.rectangle")
                }
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh & Scan", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete Movie", systemImage: "trash")
                }
            }
            .tintedCards()
        }
        .navigationTitle(movie.title)
        .task { model.configure(store: instanceStore) }
        .onReceive(model.$didDelete) { if $0 { dismiss() } }
        .overlay(alignment: .bottom) { Toast(message: model.statusMessage) { model.statusMessage = nil } }
        .sheet(item: $editing) { entry in LibraryItemEditView(entry: entry) }
        .sheet(isPresented: $showReleases) {
            NavigationStack { MovieReleasesView(model: model) }
        }
        .confirmationDialog("Delete \(movie.title)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove from library", role: .destructive) { Task { await model.delete(deleteFiles: false) } }
            Button("Remove and delete files", role: .destructive) { Task { await model.delete(deleteFiles: true) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Whether a requests service that can supply TMDB cast is configured.
    private var hasCastSource: Bool { !instanceStore.instances(ofType: .overseerr).isEmpty }

    private func movieFileMeta(_ f: RadarrMovieFile) -> FileMetadata? {
        FileMetadata(
            quality: f.quality?.displayName,
            resolution: f.mediaInfo?.resolution,
            videoCodec: f.mediaInfo?.videoCodec,
            dynamicRange: f.mediaInfo?.videoDynamicRangeType ?? f.mediaInfo?.videoDynamicRange,
            audioCodec: f.mediaInfo?.audioCodec,
            audioChannels: f.mediaInfo?.audioChannels,
            audioLanguages: f.mediaInfo?.audioLanguages,
            subtitles: f.mediaInfo?.subtitles,
            languages: f.languages?.compactMap(\.name).joined(separator: ", "),
            size: f.size ?? movie.sizeOnDisk,
            runtime: f.mediaInfo?.runTime
        )
    }

    private var statusText: String? {
        if movie.hasFile == true { return "Downloaded" }
        if movie.isAvailable == true { return "Available" }
        return movie.status?.capitalized
    }
    private var statusColor: Color {
        if movie.hasFile == true { return .green }
        if movie.isAvailable == true { return .orange }
        return .secondary
    }

    private var ratings: [DetailRating] {
        guard let r = movie.ratings else { return [] }
        var out: [DetailRating] = []
        if let v = r.imdb?.value { out.append(.init(label: "IMDb", value: String(format: "%.1f", v), color: .yellow, systemImage: "star.fill")) }
        if let v = r.tmdb?.value { out.append(.init(label: "TMDB", value: String(format: "%.1f", v), color: Theme.teal, systemImage: nil)) }
        if let v = r.rottenTomatoes?.value, v > 0 { out.append(.init(label: "RT", value: "\(Int(v))%", color: .red, systemImage: nil)) }
        if let v = r.metacritic?.value, v > 0 { out.append(.init(label: "MC", value: "\(Int(v))", color: .green, systemImage: nil)) }
        return out
    }

    private var headerData: DetailHeaderData {
        DetailHeaderData(
            instance: instance,
            posterURL: movie.imageURL(coverType: "poster"),
            fanartURL: movie.imageURL(coverType: "fanart"),
            title: movie.title,
            year: movie.year,
            runtime: movie.runtime,
            certification: movie.certification,
            status: statusText,
            statusColor: statusColor,
            genres: movie.genres ?? [],
            ratings: ratings,
            metaLine: movie.studio,
            sizeText: movie.hasFile == true ? Format.bytes(movie.sizeOnDisk) : nil
        )
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            if let studio = movie.studio, !studio.isEmpty { LabeledContent("Studio", value: studio) }
            if let runtime = movie.runtime, runtime > 0 { LabeledContent("Runtime", value: "\(runtime) min") }
            if let cert = movie.certification, !cert.isEmpty { LabeledContent("Certification", value: cert) }
            if !(movie.genres ?? []).isEmpty { LabeledContent("Genres", value: (movie.genres ?? []).joined(separator: ", ")) }
            if movie.hasFile == true { LabeledContent("Size on disk", value: Format.bytes(movie.sizeOnDisk)) }
            LabeledContent("Service", value: instance.name)
        }
    }
}

private struct MovieReleasesView: View {
    @ObservedObject var model: MovieDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sort: ReleaseSort = .seeders
    @State private var hideRejected = false
    @State private var indexerFilter: String?
    @State private var qualityFilter: String?

    private var indexers: [String] { Array(Set(model.releases.compactMap(\.indexer))).sorted() }
    private var qualities: [String] { Array(Set(model.releases.compactMap { $0.quality?.displayName })).sorted() }

    private var displayed: [RadarrRelease] {
        var r = model.releases
        if hideRejected { r = r.filter { $0.rejected != true } }
        if let indexerFilter { r = r.filter { $0.indexer == indexerFilter } }
        if let qualityFilter { r = r.filter { $0.quality?.displayName == qualityFilter } }
        switch sort {
        case .seeders: return r.sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
        case .leechers: return r.sorted { ($0.leechers ?? 0) > ($1.leechers ?? 0) }
        case .size: return r.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .quality: return r.sorted { ($0.quality?.quality?.resolution ?? 0) > ($1.quality?.quality?.resolution ?? 0) }
        case .title: return r.sorted { ($0.title ?? "") < ($1.title ?? "") }
        }
    }

    var body: some View {
        List {
            Section {
                if model.isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if displayed.isEmpty {
                    Text(model.releases.isEmpty ? "No releases found." : "No releases match the filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayed) { release in
                        ReleaseRowGeneric(
                            title: release.title ?? "Unknown release",
                            quality: release.quality?.displayName,
                            indexer: release.indexer,
                            rejected: release.rejected == true,
                            size: release.size,
                            seeders: release.seeders,
                            leechers: release.leechers
                        ) { Task { await model.grab(release) } }
                    }
                }
            } header: {
                if !model.releases.isEmpty { Text("\(displayed.count) releases") }
            }
            .tintedCards()
        }
        .navigationTitle("Releases")
        .toolbar {
            if !model.releases.isEmpty { ToolbarItem(placement: .topBarLeading) { filterMenu } }
        }
        .doneToolbar { dismiss() }
        .task { await model.loadReleases() }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(ReleaseSort.allCases) { Text($0.label).tag($0) }
            }
            Section("Filter") {
                Toggle("Hide rejected", isOn: $hideRejected)
                if indexers.count > 1 {
                    Picker("Indexer", selection: $indexerFilter) {
                        Text("All Indexers").tag(String?.none)
                        ForEach(indexers, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
                if qualities.count > 1 {
                    Picker("Quality", selection: $qualityFilter) {
                        Text("All Qualities").tag(String?.none)
                        ForEach(qualities, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
            }
        } label: {
            Label("Filter & Sort", systemImage: "line.3.horizontal.decrease.circle").labelStyle(.iconOnly)
        }
    }
}
