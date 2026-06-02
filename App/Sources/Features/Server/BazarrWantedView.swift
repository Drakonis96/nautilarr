import SwiftUI
import NautilarrCore
import BazarrKit

/// What a subtitle search targets — an episode or a movie.
enum SubtitleTarget: Identifiable {
    case episode(seriesId: Int, episodeId: Int, title: String, subtitle: String)
    case movie(radarrId: Int, title: String)

    var id: String {
        switch self {
        case let .episode(_, episodeId, _, _): return "e\(episodeId)"
        case let .movie(radarrId, _): return "m\(radarrId)"
        }
    }
    var title: String {
        switch self {
        case let .episode(_, _, title, _): return title
        case let .movie(_, title): return title
        }
    }
    var subtitle: String {
        switch self {
        case let .episode(_, _, _, subtitle): return subtitle
        case .movie: return "Movie"
        }
    }
}

/// A manual-search request: which item, and (optionally) which language to
/// pre-select. Drives the search sheet so per-language buttons jump straight to
/// the right filter.
struct SubtitleSearchRequest: Identifiable {
    let target: SubtitleTarget
    var language: String?
    var id: String { "\(target.id)-\(language ?? "any")" }
}

/// Bazarr "wanted" lists — episodes and movies missing subtitles. Tapping an
/// item opens a manual subtitle search where you can pick a language and grab a
/// subtitle, just like Bazarr's own UI.
struct BazarrWantedView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore

    private enum Tab: Hashable { case episodes, movies }

    @State private var episodes: [BazarrWantedEpisode] = []
    @State private var movies: [BazarrWantedMovie] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var tab: Tab = .episodes
    @State private var searchRequest: SubtitleSearchRequest?

    private var filteredEpisodes: [BazarrWantedEpisode] {
        guard !searchText.isEmpty else { return episodes }
        return episodes.filter {
            ($0.seriesTitle ?? "").localizedStandardContains(searchText)
            || ($0.episodeTitle ?? "").localizedStandardContains(searchText)
        }
    }
    private var filteredMovies: [BazarrWantedMovie] {
        guard !searchText.isEmpty else { return movies }
        return movies.filter { ($0.title ?? "").localizedStandardContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Filter wanted items", text: $searchText)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
            Picker("", selection: $tab) {
                Text("Episodes (\(episodes.count))").tag(Tab.episodes)
                Text("Movies (\(movies.count))").tag(Tab.movies)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if let error { Section { ErrorBanner(message: error) } }
                if tab == .episodes {
                    if filteredEpisodes.isEmpty && !isLoading { emptyRow("No episodes missing subtitles.") }
                    ForEach(filteredEpisodes) { episode in
                        WantedRow(
                            title: episode.seriesTitle ?? "Series",
                            subtitle: [episode.episodeNumber, episode.episodeTitle].compactMap { $0 }.joined(separator: " · "),
                            languages: episode.missingSubtitles ?? [],
                            target: .episode(
                                seriesId: episode.sonarrSeriesId ?? 0,
                                episodeId: episode.sonarrEpisodeId ?? 0,
                                title: episode.seriesTitle ?? "Series",
                                subtitle: [episode.episodeNumber, episode.episodeTitle].compactMap { $0 }.joined(separator: " · ")),
                            present: { searchRequest = $0 })
                    }
                } else {
                    if filteredMovies.isEmpty && !isLoading { emptyRow("No movies missing subtitles.") }
                    ForEach(filteredMovies) { movie in
                        WantedRow(
                            title: movie.title ?? "Movie",
                            subtitle: nil,
                            languages: movie.missingSubtitles ?? [],
                            target: .movie(radarrId: movie.radarrId ?? 0, title: movie.title ?? "Movie"),
                            present: { searchRequest = $0 })
                    }
                }
            }
        }
        .navigationTitle(instance.name)
        .overlay { if isLoading && episodes.isEmpty && movies.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $searchRequest) { request in
            BazarrSubtitleSearchView(instance: instance, target: request.target, initialLanguage: request.language)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).font(.subheadline)
    }

    private func load() async {
        guard let client = instanceStore.bazarrClient(for: instance) else { return }
        isLoading = true
        defer { isLoading = false }
        var firstError: String?
        do { episodes = try await client.allWantedEpisodes() } catch { firstError = describe(error) }
        do { movies = try await client.allWantedMovies() } catch { if firstError == nil { firstError = describe(error) } }
        error = firstError
    }

    private func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}

private struct WantedRow: View {
    let title: String
    let subtitle: String?
    let languages: [BazarrSubtitleLanguage]
    let target: SubtitleTarget
    let present: (SubtitleSearchRequest) -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if !languages.isEmpty {
                    // Each missing language is a button that searches for that
                    // language directly.
                    HStack(spacing: 6) {
                        ForEach(languages, id: \.self) { lang in
                            Button {
                                present(.init(target: target, language: lang.code2 ?? lang.name))
                            } label: {
                                Label(label(for: lang), systemImage: "magnifyingglass")
                                    .font(.caption2.weight(.semibold))
                                    .labelStyle(.titleAndIcon)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                present(.init(target: target, language: nil))
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.teal)
            }
            .buttonStyle(.plain)
            .help("Search all languages")
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func label(for lang: BazarrSubtitleLanguage) -> String {
        var text = (lang.code2 ?? lang.name ?? "?").uppercased()
        if lang.hi == true { text += " HI" }
        if lang.forced == true { text += " F" }
        return text
    }
}
