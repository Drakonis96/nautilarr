import SwiftUI
import NautilarrCore
import BazarrKit

/// Manual subtitle search for one episode/movie: pick a language, see provider
/// results, and download — mirroring Bazarr's own manual-search flow.
struct BazarrSubtitleSearchView: View {
    let instance: ServiceInstance
    let target: SubtitleTarget
    /// Language to pre-select once results arrive (lenient prefix match), e.g.
    /// when the user tapped a specific missing-language button.
    var initialLanguage: String?
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var results: [BazarrSubtitleResult] = []
    @State private var selectedLanguage: String?
    @State private var isLoading = false
    @State private var status: String?

    /// Languages that actually appear in the results — the ones worth filtering by.
    private var availableLanguages: [String] {
        Array(Set(results.compactMap { $0.language })).sorted()
    }

    private var filtered: [BazarrSubtitleResult] {
        guard let selectedLanguage else { return results }
        return results.filter { $0.language == selectedLanguage }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if availableLanguages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All", selected: selectedLanguage == nil) { selectedLanguage = nil }
                            ForEach(availableLanguages, id: \.self) { lang in
                                chip(lang.uppercased(), selected: selectedLanguage == lang) { selectedLanguage = lang }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }
                List {
                    Section {
                        Text(target.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .tintedCards()
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .tintedCards()
                    } else if filtered.isEmpty {
                        Text("No subtitles found for this selection.").foregroundStyle(.secondary).font(.subheadline)
                            .tintedCards()
                    }
                    ForEach(filtered) { result in resultRow(result) }
                        .tintedCards()
                }
            }
            .navigationTitle(target.title)
            .doneToolbar { dismiss() }
            .overlay(alignment: .bottom) { Toast(message: status) { status = nil } }
            .task { await load() }
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.teal : Color.secondary.opacity(0.2), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func resultRow(_ result: BazarrSubtitleResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.releaseInfo?.first ?? result.subtitle ?? "Subtitle").font(.subheadline).lineLimit(2)
            HStack(spacing: 8) {
                if let provider = result.provider { StatusBadge(text: provider, color: Theme.teal) }
                if let language = result.language { StatusBadge(text: language.uppercased()) }
                if let score = result.score { StatusBadge(text: "Score \(Int(score))", color: .green) }
            }
            HStack {
                if let uploader = result.uploader { Text(uploader).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button("Download") { Task { await download(result) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let client = instanceStore.bazarrClient(for: instance) else { return }
        isLoading = true
        defer { isLoading = false }
        switch target {
        case let .episode(_, episodeId, _, _):
            results = (try? await client.episodeSubtitleResults(episodeId: episodeId))?
                .sorted { ($0.score ?? 0) > ($1.score ?? 0) } ?? []
        case let .movie(radarrId, _):
            results = (try? await client.movieSubtitleResults(radarrId: radarrId))?
                .sorted { ($0.score ?? 0) > ($1.score ?? 0) } ?? []
        }
        // Pre-select the requested language if the results actually carry it
        // (lenient match: "es" selects "es-mx", etc.).
        if selectedLanguage == nil, let initialLanguage {
            let wanted = initialLanguage.lowercased()
            selectedLanguage = availableLanguages.first {
                let lang = $0.lowercased()
                return lang == wanted || lang.hasPrefix(wanted) || wanted.hasPrefix(lang)
            }
        }
    }

    private func download(_ result: BazarrSubtitleResult) async {
        guard let client = instanceStore.bazarrClient(for: instance),
              let provider = result.provider, let subtitle = result.subtitle, let language = result.language else {
            status = "This result is missing data needed to download."
            return
        }
        do {
            switch target {
            case let .episode(seriesId, episodeId, _, _):
                try await client.downloadEpisodeSubtitle(seriesId: seriesId, episodeId: episodeId, language: language, provider: provider, subtitle: subtitle)
            case let .movie(radarrId, _):
                try await client.downloadMovieSubtitle(radarrId: radarrId, language: language, provider: provider, subtitle: subtitle)
            }
            status = "Subtitle requested."
        } catch {
            status = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
