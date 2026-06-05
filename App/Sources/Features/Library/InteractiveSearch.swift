import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit

/// A service-neutral release for the interactive-search UI, decoupled from
/// Sonarr/Radarr so a single results screen serves movies, episodes, season packs
/// and the Downloads "open interactive search" deep-link. Each row carries its own
/// grab action.
struct InteractiveRelease: Identifiable {
    let id: String
    let title: String
    let quality: String?
    /// Vertical resolution, used only for the "Quality" sort.
    let qualityRank: Int
    let indexer: String?
    let rejected: Bool
    let size: Int64?
    let seeders: Int?
    let leechers: Int?
    /// Pushes this release to the download client; returns a status string.
    let grab: @MainActor () async -> String
}

extension InteractiveRelease {
    init(_ r: SonarrRelease, grab: @escaping @MainActor () async -> String) {
        self.init(id: r.id, title: r.title ?? "Unknown release",
                  quality: r.quality?.displayName, qualityRank: r.quality?.quality?.resolution ?? 0,
                  indexer: r.indexer, rejected: r.rejected == true, size: r.size,
                  seeders: r.seeders, leechers: r.leechers, grab: grab)
    }
    init(_ r: RadarrRelease, grab: @escaping @MainActor () async -> String) {
        self.init(id: r.id, title: r.title ?? "Unknown release",
                  quality: r.quality?.displayName, qualityRank: r.quality?.quality?.resolution ?? 0,
                  indexer: r.indexer, rejected: r.rejected == true, size: r.size,
                  seeders: r.seeders, leechers: r.leechers, grab: grab)
    }
}

/// The single interactive-search results screen, shared across every entry point.
/// Surfaces load failures (timeouts / 5xx / auth) explicitly — the previous
/// per-screen `try?` made every failure read as "No releases found", which is why
/// series/episode search looked broken while movies worked. Provides the same
/// sort + indexer/quality filters everywhere.
struct InteractiveReleaseSearchView: View {
    let title: String
    var currentFile: FileMetadata? = nil
    let load: () async throws -> [InteractiveRelease]

    @State private var releases: [InteractiveRelease] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var sort: ReleaseSort = .seeders
    @State private var hideRejected = false
    @State private var indexerFilter: String?
    @State private var qualityFilter: String?

    private var indexers: [String] { Array(Set(releases.compactMap(\.indexer))).sorted() }
    private var qualities: [String] { Array(Set(releases.compactMap(\.quality))).sorted() }

    private var displayed: [InteractiveRelease] {
        var r = releases
        if hideRejected { r = r.filter { !$0.rejected } }
        if let indexerFilter { r = r.filter { $0.indexer == indexerFilter } }
        if let qualityFilter { r = r.filter { $0.quality == qualityFilter } }
        switch sort {
        case .seeders: return r.sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
        case .leechers: return r.sorted { ($0.leechers ?? 0) > ($1.leechers ?? 0) }
        case .size: return r.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .quality: return r.sorted { $0.qualityRank > $1.qualityRank }
        case .title: return r.sorted { $0.title < $1.title }
        }
    }

    var body: some View {
        List {
            if let currentFile, currentFile.hasAny {
                Section("Current File") { FileInfoRows(meta: currentFile) }
                    .tintedCards()
            }
            Section {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        ErrorBanner(message: errorMessage)
                        Button { Task { await reload() } } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                    }
                } else if displayed.isEmpty {
                    Text(releases.isEmpty ? "No releases found." : "No releases match the filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayed) { release in
                        ReleaseRowGeneric(
                            title: release.title,
                            quality: release.quality,
                            indexer: release.indexer,
                            rejected: release.rejected,
                            size: release.size,
                            seeders: release.seeders,
                            leechers: release.leechers
                        ) { Task { toast = await release.grab() } }
                    }
                }
            } header: {
                if !releases.isEmpty { Text("\(displayed.count) releases") }
            }
            .tintedCards()
        }
        .navigationTitle(title)
        .toolbar {
            if !releases.isEmpty { ToolbarItem(placement: .primaryAction) { filterMenu } }
        }
        .task { await reload() }
        .overlay(alignment: .bottom) { Toast(message: toast) { toast = nil } }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            releases = try await load()
        } catch {
            releases = []
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
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

// MARK: - Loaders

/// Builds the `load` closures that feed `InteractiveReleaseSearchView` from a
/// Sonarr/Radarr client. Each release's grab is wired to the same client.
enum InteractiveSearchLoader {
    static func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }

    static func sonarrEpisode(_ client: SonarrClient, episodeId: Int) -> () async throws -> [InteractiveRelease] {
        { try await client.releases(episodeId: episodeId).map { rel in
            InteractiveRelease(rel) {
                do { try await client.grab(rel); return "Sent to download client." }
                catch { return describe(error) }
            }
        } }
    }

    static func sonarrSeason(_ client: SonarrClient, seriesId: Int, seasonNumber: Int) -> () async throws -> [InteractiveRelease] {
        { try await client.releases(seriesId: seriesId, seasonNumber: seasonNumber).map { rel in
            InteractiveRelease(rel) {
                do { try await client.grab(rel); return "Sent to download client." }
                catch { return describe(error) }
            }
        } }
    }

    static func radarrMovie(_ client: RadarrClient, movieId: Int) -> () async throws -> [InteractiveRelease] {
        { try await client.releases(movieId: movieId)
            .sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
            .map { rel in
                InteractiveRelease(rel) {
                    do { try await client.grab(rel); return "Sent to download client." }
                    catch { return describe(error) }
                }
            } }
    }
}
