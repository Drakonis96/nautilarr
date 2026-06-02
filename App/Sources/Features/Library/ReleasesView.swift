import SwiftUI
import SonarrKit

/// Interactive search results for an episode, with the currently-linked file's
/// metadata, filter/sort controls, and a grab action per release.
struct ReleasesView: View {
    let episode: SonarrEpisode
    @ObservedObject var model: SeriesDetailViewModel

    @State private var releases: [SonarrRelease] = []
    @State private var isLoading = true
    @State private var toast: String?
    @State private var sort: ReleaseSort = .seeders
    @State private var hideRejected = false
    @State private var indexerFilter: String?
    @State private var qualityFilter: String?

    private var indexers: [String] { Array(Set(releases.compactMap(\.indexer))).sorted() }
    private var qualities: [String] { Array(Set(releases.compactMap { $0.quality?.displayName })).sorted() }

    private var displayed: [SonarrRelease] {
        var r = releases
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
            if episode.hasFile == true, let file = episode.episodeFile, let m = Self.meta(file), m.hasAny {
                Section("Current File") { FileInfoRows(meta: m) }
                    .tintedCards()
            }
            Section {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if displayed.isEmpty {
                    Text(releases.isEmpty ? "No releases found." : "No releases match the filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayed) { release in
                        ReleaseRow(release: release) { Task { toast = await model.grab(release) } }
                    }
                }
            } header: {
                if !releases.isEmpty { Text("\(displayed.count) releases") }
            }
            .tintedCards()
        }
        .navigationTitle(episode.seasonEpisodeCode)
        .toolbar {
            if !releases.isEmpty { ToolbarItem(placement: .primaryAction) { filterMenu } }
        }
        .task {
            releases = await model.releases(for: episode)
            isLoading = false
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation { self.toast = nil }
                    }
            }
        }
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

    static func meta(_ f: SonarrEpisodeFile) -> FileMetadata? {
        FileMetadata(
            quality: f.quality?.displayName,
            resolution: f.mediaInfo?.resolution,
            videoCodec: f.mediaInfo?.videoCodec,
            dynamicRange: f.mediaInfo?.videoDynamicRange,
            audioCodec: f.mediaInfo?.audioCodec,
            audioChannels: f.mediaInfo?.audioChannels,
            audioLanguages: f.mediaInfo?.audioLanguages,
            subtitles: f.mediaInfo?.subtitles,
            languages: f.languages?.compactMap(\.name).joined(separator: ", "),
            size: f.size,
            runtime: f.mediaInfo?.runTime
        )
    }
}

private struct ReleaseRow: View {
    let release: SonarrRelease
    let onGrab: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(release.title ?? "Unknown release")
                .font(.subheadline).lineLimit(2)
            HStack(spacing: 10) {
                if let q = release.quality?.displayName { StatusBadge(text: q, color: Theme.teal) }
                if let indexer = release.indexer { StatusBadge(text: indexer) }
                if release.rejected == true { StatusBadge(text: "Rejected", color: .orange) }
            }
            HStack(spacing: 14) {
                Label(Format.bytes(release.size), systemImage: "internaldrive")
                if let s = release.seeders { Label("\(s)", systemImage: "arrow.up") }
                if let l = release.leechers { Label("\(l)", systemImage: "arrow.down") }
                Spacer()
                Button("Grab", action: onGrab)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
