import SwiftUI
import NautilarrCore
import LidarrKit

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    @Published var albums: [LidarrAlbum] = []
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var didDelete = false
    @Published var monitored: Bool
    @Published var releases: [LidarrRelease] = []
    @Published var isSearchingReleases = false

    private let instance: ServiceInstance
    private let artist: LidarrArtist
    private weak var store: InstanceStore?
    private var client: LidarrClient? { store?.lidarrClient(for: instance) }

    init(instance: ServiceInstance, artist: LidarrArtist) {
        self.instance = instance
        self.artist = artist
        self.monitored = artist.monitored ?? false
    }
    func configure(store: InstanceStore) { self.store = store }

    func loadAlbums() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do { albums = try await client.albums(artistId: artist.id).sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) } }
        catch { statusMessage = describe(error) }
    }

    func automaticSearch() async { await run(.artistSearch(artistId: artist.id), success: "Searching for this artist…") }
    func refresh() async { await run(.refreshArtist(artistId: artist.id), success: "Refreshing artist…") }
    func searchAlbum(_ album: LidarrAlbum) async { await run(.albumSearch(albumIds: [album.id]), success: "Searching “\(album.title)”…") }

    // MARK: - Monitoring

    func setMonitored(_ value: Bool) async {
        monitored = value
        guard let client else { return }
        do {
            try await client.editArtists(ids: [artist.id], monitored: value)
            statusMessage = value ? "Now monitoring." : "No longer monitoring."
        } catch {
            monitored = !value
            statusMessage = describe(error)
        }
    }

    func isAlbumMonitored(_ album: LidarrAlbum) -> Bool {
        albums.first { $0.id == album.id }?.monitored ?? false
    }

    func setAlbumMonitored(_ album: LidarrAlbum, monitored: Bool) async {
        guard let client else { return }
        setAlbumMonitoredLocally(album.id, monitored: monitored)
        do {
            try await client.setAlbumsMonitored(ids: [album.id], monitored: monitored)
        } catch {
            setAlbumMonitoredLocally(album.id, monitored: !monitored)
            statusMessage = describe(error)
        }
    }

    private func setAlbumMonitoredLocally(_ id: Int, monitored: Bool) {
        if let i = albums.firstIndex(where: { $0.id == id }) { albums[i].monitored = monitored }
    }

    // MARK: - Interactive search

    func loadReleases(for album: LidarrAlbum) async {
        guard let client else { return }
        isSearchingReleases = true
        defer { isSearchingReleases = false }
        releases = ((try? await client.releases(albumId: album.id)) ?? [])
            .sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
    }

    func grab(_ release: LidarrRelease) async {
        guard let client else { return }
        do { try await client.grab(release); statusMessage = "Sent to download client." }
        catch { statusMessage = describe(error) }
    }

    private func run(_ command: LidarrCommandRequest, success: String) async {
        guard let client else { return }
        do { _ = try await client.runCommand(command); statusMessage = success }
        catch { statusMessage = describe(error) }
    }

    func delete(deleteFiles: Bool) async {
        guard let client else { return }
        do { try await client.deleteArtist(id: artist.id, deleteFiles: deleteFiles); didDelete = true }
        catch { statusMessage = describe(error) }
    }

    private func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}

/// Artist detail: artwork, overview, albums and actions.
struct ArtistDetailView: View {
    let instance: ServiceInstance
    let artist: LidarrArtist
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ArtistDetailViewModel
    @State private var showDeleteConfirm = false
    @State private var editing: MediaEntry?
    @State private var interactiveAlbum: LidarrAlbum?

    init(instance: ServiceInstance, artist: LidarrArtist) {
        self.instance = instance
        self.artist = artist
        _model = StateObject(wrappedValue: ArtistDetailViewModel(instance: instance, artist: artist))
    }

    var body: some View {
        List {
            header
                .tintedCards()
            if let overview = artist.overview, !overview.isEmpty {
                Section { Text(overview).font(.subheadline) }
                    .tintedCards()
            }
            Section {
                Toggle("Monitored", isOn: Binding(
                    get: { model.monitored },
                    set: { value in Task { await model.setMonitored(value) } }
                ))
                Button { editing = .artist(instance: instance, artist: artist) } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                Button { Task { await model.automaticSearch() } } label: {
                    Label("Automatic Search", systemImage: "magnifyingglass")
                }
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh & Scan", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete Artist", systemImage: "trash")
                }
            }
            .tintedCards()
            Section("Albums") {
                if model.isLoading { ProgressView() }
                ForEach(model.albums) { album in
                    AlbumRow(
                        album: album,
                        monitored: model.isAlbumMonitored(album),
                        onToggleMonitor: { Task { await model.setAlbumMonitored(album, monitored: !model.isAlbumMonitored(album)) } },
                        onAutomaticSearch: { Task { await model.searchAlbum(album) } },
                        onInteractiveSearch: { interactiveAlbum = album }
                    )
                }
            }
            .tintedCards()
        }
        .navigationTitle(artist.artistName)
        .task {
            model.configure(store: instanceStore)
            await model.loadAlbums()
        }
        .onReceive(model.$didDelete) { if $0 { dismiss() } }
        .overlay(alignment: .bottom) { Toast(message: model.statusMessage) { model.statusMessage = nil } }
        .sheet(item: $editing) { entry in LibraryItemEditView(entry: entry) }
        .sheet(item: $interactiveAlbum) { album in
            NavigationStack { AlbumReleasesView(album: album, model: model) }
        }
        .confirmationDialog("Delete \(artist.artistName)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove from library", role: .destructive) { Task { await model.delete(deleteFiles: false) } }
            Button("Remove and delete files", role: .destructive) { Task { await model.delete(deleteFiles: true) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                PosterTile(entry: .artist(instance: instance, artist: artist), showsTitle: false)
                    .frame(width: 110)
                VStack(alignment: .leading, spacing: 8) {
                    if let status = artist.status {
                        StatusBadge(text: status.capitalized, color: status == "continuing" ? .green : .secondary)
                    }
                    if let stats = artist.statistics {
                        Text("\(stats.albumCount ?? 0) albums").font(.caption).foregroundStyle(.secondary)
                        Text("\(stats.trackFileCount ?? 0)/\(stats.totalTrackCount ?? 0) tracks").font(.caption).foregroundStyle(.secondary)
                        Text(Format.bytes(stats.sizeOnDisk)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(instance.name).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }
}

private struct AlbumRow: View {
    let album: LidarrAlbum
    let monitored: Bool
    let onToggleMonitor: () -> Void
    let onAutomaticSearch: () -> Void
    let onInteractiveSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: (album.statistics?.trackFileCount ?? 0) > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle((album.statistics?.trackFileCount ?? 0) > 0 ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    if let type = album.albumType { Text(type) }
                    if let date = album.releaseDate { Text(date, format: .dateTime.year()) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onToggleMonitor() } label: {
                Image(systemName: monitored ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(monitored ? Theme.teal : .secondary)
            }
            .buttonStyle(.borderless)
            Menu {
                Button { onAutomaticSearch() } label: { Label("Automatic Search", systemImage: "magnifyingglass") }
                Button { onInteractiveSearch() } label: { Label("Interactive Search", systemImage: "list.bullet.rectangle") }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Interactive release picker for a single album, mirroring the movie flow.
private struct AlbumReleasesView: View {
    let album: LidarrAlbum
    @ObservedObject var model: ArtistDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.isSearchingReleases {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .tintedCards()
            } else if model.releases.isEmpty {
                Text("No releases found.").foregroundStyle(.secondary)
                    .tintedCards()
            } else {
                ForEach(model.releases) { release in
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
                .tintedCards()
            }
        }
        .navigationTitle(album.title)
        .doneToolbar { dismiss() }
        .task { await model.loadReleases(for: album) }
    }
}
