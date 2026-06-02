import SwiftUI
import NautilarrCore
import SonarrKit

/// Series detail: artwork, overview, stats, per-season episodes and actions
/// (automatic search, refresh, delete, interactive search).
struct SeriesDetailView: View {
    let item: LibraryItem
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SeriesDetailViewModel
    @State private var showDeleteConfirm = false
    @State private var editing: MediaEntry?

    init(item: LibraryItem) {
        self.item = item
        _model = StateObject(wrappedValue: SeriesDetailViewModel(item: item))
    }

    var body: some View {
        List {
            Section { MediaDetailHeader(data: headerData) }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            if let overview = item.series.overview, !overview.isEmpty {
                Section("Overview") { Text(overview).font(.subheadline) }
            }

            // Details right under the synopsis; cast (if any) after it.
            detailsSection

            if hasCastSource {
                Section { MediaCastStrip(mediaType: "tv", tmdbId: series.tmdbId, title: series.title, year: series.year) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            actionsSection
            seasonsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.series.title)
        .navigationBarTitleDisplayModeInline()
        .task {
            model.configure(store: instanceStore)
            await model.loadEpisodes()
        }
        .onReceive(model.$didDelete) { if $0 { dismiss() } }
        .overlay(alignment: .bottom) { statusToast }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .series(instance: item.instance, series: item.series) } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(item: $editing) { entry in LibraryItemEditView(entry: entry) }
        .confirmationDialog("Delete \(item.series.title)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove from library", role: .destructive) { Task { await model.delete(deleteFiles: false) } }
            Button("Remove and delete files", role: .destructive) { Task { await model.delete(deleteFiles: true) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var series: SonarrSeries { item.series }

    /// Whether a requests service that can supply TMDB cast is configured.
    private var hasCastSource: Bool { !instanceStore.instances(ofType: .overseerr).isEmpty }

    private var ratings: [DetailRating] {
        guard let value = series.ratings?.value, value > 0 else { return [] }
        return [DetailRating(label: "Rating", value: String(format: "%.1f", value), color: .yellow, systemImage: "star.fill")]
    }

    private var headerData: DetailHeaderData {
        DetailHeaderData(
            instance: item.instance,
            posterURL: series.imageURL(coverType: "poster"),
            fanartURL: series.imageURL(coverType: "fanart"),
            title: series.title,
            year: series.year,
            runtime: series.runtime,
            certification: series.certification,
            status: series.status?.capitalized,
            statusColor: series.status == "continuing" ? .green : .secondary,
            genres: series.genres ?? [],
            ratings: ratings,
            metaLine: series.network,
            sizeText: series.statistics.map { Format.bytes($0.sizeOnDisk) }
        )
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            if let network = series.network, !network.isEmpty { LabeledContent("Network", value: network) }
            if let stats = series.statistics {
                LabeledContent("Episodes", value: "\(stats.episodeFileCount ?? 0)/\(stats.totalEpisodeCount ?? 0)")
                LabeledContent("Size on disk", value: Format.bytes(stats.sizeOnDisk))
            }
            if let cert = series.certification, !cert.isEmpty { LabeledContent("Certification", value: cert) }
            if !(series.genres ?? []).isEmpty { LabeledContent("Genres", value: (series.genres ?? []).joined(separator: ", ")) }
            LabeledContent("Service", value: item.instance.name)
        }
    }

    private var actionsSection: some View {
        Section {
            Toggle("Monitored", isOn: Binding(
                get: { model.seriesMonitored },
                set: { value in Task { await model.setSeriesMonitored(value) } }
            ))
            Button { editing = .series(instance: item.instance, series: item.series) } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            Button { Task { await model.automaticSearchSeries() } } label: {
                Label("Automatic Search", systemImage: "magnifyingglass")
            }
            Button { Task { await model.refresh() } } label: {
                Label("Refresh & Scan", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete Series", systemImage: "trash")
            }
        }
    }

    private var seasonsSection: some View {
        ForEach(model.seasonNumbers, id: \.self) { season in
            Section {
                ForEach(model.episodesBySeason[season] ?? []) { episode in
                    NavigationLink {
                        ReleasesView(episode: episode, model: model)
                    } label: {
                        EpisodeRow(episode: episode)
                    }
                    .swipeActions(edge: .leading) {
                        let monitored = episode.monitored == true
                        Button {
                            Task { await model.setEpisodeMonitored(episode, monitored: !monitored) }
                        } label: {
                            Label(monitored ? "Unmonitor" : "Monitor",
                                  systemImage: monitored ? "bookmark.slash" : "bookmark")
                        }
                        .tint(monitored ? .gray : Theme.teal)
                    }
                }
            } header: {
                HStack {
                    Button {
                        Task { await model.setSeasonMonitored(season, monitored: !model.isSeasonMonitored(season)) }
                    } label: {
                        Image(systemName: model.isSeasonMonitored(season) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(model.isSeasonMonitored(season) ? Theme.teal : .secondary)
                    }
                    .buttonStyle(.borderless)
                    Text(season == 0 ? "Specials" : "Season \(season)")
                    Spacer()
                    Button("Search") { Task { await model.searchSeason(season) } }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private var statusToast: some View {
        if let message = model.statusMessage {
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { model.statusMessage = nil }
                }
        }
    }
}

private struct EpisodeRow: View {
    let episode: SonarrEpisode

    var body: some View {
        HStack {
            Image(systemName: episode.hasFile == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(episode.hasFile == true ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(episode.seasonEpisodeCode) · \(episode.title ?? "TBA")")
                    .font(.subheadline).lineLimit(1)
                if let date = episode.airDateUtc {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if episode.monitored == true {
                Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.teal)
            }
        }
    }
}

// MARK: - iOS 16 / Catalyst compatible inline title modifier

private extension View {
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}

