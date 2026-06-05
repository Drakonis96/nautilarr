import SwiftUI
import NautilarrCore
import RadarrKit

@MainActor
final class MovieDetailViewModel: ObservableObject {
    @Published var statusMessage: String?
    @Published var didDelete = false
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

    /// Interactive-search loader for this movie (surfaces failures in the shared
    /// results view, which fixes the "always empty" illusion from a silent `try?`).
    func searchLoader() -> () async throws -> [InteractiveRelease] {
        guard let client else { return { throw APIError.invalidResponse } }
        return InteractiveSearchLoader.radarrMovie(client, movieId: movie.id)
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

            // Cast + recommendations only when a requests service
            // (Overseerr/Jellyseerr) is set up — otherwise they'd always be empty
            // and just leave a gap. Each strip emits its own grouped `Section`,
            // matching the other cards.
            if hasCastSource {
                MediaCastStrip(mediaType: "movie", tmdbId: movie.tmdbId, title: movie.title, year: movie.year)
                MediaRecommendationsStrip(mediaType: "movie", tmdbId: movie.tmdbId,
                                          title: movie.title, year: movie.year) { model.statusMessage = $0 }
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
                NavigationLink {
                    InteractiveReleaseSearchView(
                        title: "Releases",
                        currentFile: currentFileMeta,
                        load: model.searchLoader()
                    )
                } label: {
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

    /// The linked file's metadata, shown atop interactive search when downloaded.
    private var currentFileMeta: FileMetadata? {
        guard movie.hasFile == true, let file = movie.movieFile,
              let m = movieFileMeta(file), m.hasAny else { return nil }
        return m
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
        if let v = r.imdb?.value { out.append(.init(label: "IMDb", value: String(format: "%.1f", v), color: Color(red: 0.96, green: 0.77, blue: 0.09), systemImage: "star.fill", assetName: "rating-imdb")) }
        if let v = r.tmdb?.value { out.append(.init(label: "TMDB", value: String(format: "%.1f", v), color: Color(red: 0.0, green: 0.71, blue: 0.89), systemImage: nil, assetName: "rating-tmdb")) }
        if let v = r.rottenTomatoes?.value, v > 0 { out.append(.init(label: "RT", value: "\(Int(v))%", color: Color(red: 0.98, green: 0.20, blue: 0.04), systemImage: nil, assetName: "rating-rt")) }
        if let v = r.metacritic?.value, v > 0 { out.append(.init(label: "MC", value: "\(Int(v))", color: Color(red: 1.0, green: 0.80, blue: 0.20), systemImage: nil, assetName: "rating-mc")) }
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

