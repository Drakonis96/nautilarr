import SwiftUI
import NautilarrCore
import SonarrKit

// MARK: - Episode detail (metadata first)

/// An episode's detail screen. By default it shows the episode's metadata and —
/// when downloaded — the linked file's technical details, *without* kicking off an
/// indexer search. Two actions are offered: an automatic (indexer) search and an
/// interactive search, the latter pushing the shared results section with the
/// usual filters. This mirrors the movie detail flow.
struct EpisodeDetailView: View {
    let episode: SonarrEpisode
    @ObservedObject var model: SeriesDetailViewModel
    @State private var toast: String?

    private var fileMeta: FileMetadata? {
        guard episode.hasFile == true, let file = episode.episodeFile else { return nil }
        let m = episodeFileMeta(file)
        return m.hasAny ? m : nil
    }

    var body: some View {
        List {
            Section {
                if let title = episode.title, !title.isEmpty { LabeledContent("Title", value: title) }
                if let date = episode.airDateUtc {
                    LabeledContent("Air date") { Text(date, format: .dateTime.year().month().day()) }
                }
                if let runtime = episode.runtime, runtime > 0 { LabeledContent("Runtime", value: "\(runtime) min") }
                LabeledContent("Status", value: episode.hasFile == true ? "Downloaded" : "Missing")
            } header: {
                Text(episode.seasonEpisodeCode)
            }
            .tintedCards()

            if let overview = episode.overview, !overview.isEmpty {
                Section("Overview") { Text(overview).font(.subheadline) }
                    .tintedCards()
            }

            if let meta = fileMeta {
                Section("File") { FileInfoRows(meta: meta) }
                    .tintedCards()
            }

            Section {
                Button {
                    Task { toast = await model.automaticSearchEpisode(episode) }
                } label: {
                    Label("Automatic Search", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    InteractiveReleaseSearchView(
                        title: episode.seasonEpisodeCode,
                        currentFile: fileMeta,
                        load: model.episodeSearchLoader(episode)
                    )
                } label: {
                    Label("Interactive Search", systemImage: "list.bullet.rectangle")
                }
            }
            .tintedCards()
        }
        .navigationTitle(episode.seasonEpisodeCode)
        .overlay(alignment: .bottom) { Toast(message: toast) { toast = nil } }
    }
}

/// Builds neutral file metadata from a Sonarr episode file.
func episodeFileMeta(_ f: SonarrEpisodeFile) -> FileMetadata {
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
