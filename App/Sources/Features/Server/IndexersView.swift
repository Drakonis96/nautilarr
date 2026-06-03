import SwiftUI
import NautilarrCore
import ProwlarrKit
import TorznabKit

/// Top-level "Indexers" destination, unifying every indexer service: Prowlarr
/// (full search + management) and Jackett / NZBHydra2 (Torznab search). With one
/// service it's shown directly; with several, a chip bar filters between them.
struct IndexersView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var selectedID: UUID?

    private var indexers: [ServiceInstance] {
        instanceStore.instances(ofType: .prowlarr)
            + instanceStore.instances(ofType: .jackett)
            + instanceStore.instances(ofType: .nzbhydra2)
    }

    var body: some View {
        Group {
            if indexers.isEmpty {
                ContentUnavailableLabel(
                    "No indexers",
                    systemImage: "magnifyingglass.circle",
                    description: "Add a Prowlarr, Jackett or NZBHydra2 service in Settings to search and manage your indexers."
                )
            } else if indexers.count == 1 {
                indexerView(indexers[0])
            } else {
                VStack(spacing: 0) {
                    instancePicker
                    indexerView(selectedInstance)
                }
            }
        }
    }

    private var selectedInstance: ServiceInstance {
        indexers.first { $0.id == selectedID } ?? indexers[0]
    }

    private var instancePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(indexers) { instance in
                    FilterChip(title: instance.name, serviceType: instance.type,
                               isSelected: instance.id == selectedInstance.id) {
                        selectedID = instance.id
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(height: 56)
    }

    @ViewBuilder
    private func indexerView(_ instance: ServiceInstance) -> some View {
        Group {
            if instance.type == .prowlarr {
                ProwlarrHubView(instance: instance)
            } else {
                TorznabView(instance: instance)
            }
        }
        // Reset child state (search term/results) when switching indexers.
        .id(instance.id)
    }
}

/// Segmented Indexers / Search for one Prowlarr instance. Indexers is the
/// default (left) view; Search sits on the right.
private struct ProwlarrHubView: View {
    let instance: ServiceInstance
    private enum Segment: Hashable { case indexers, search }
    @State private var segment: Segment = .indexers

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("Indexers").tag(Segment.indexers)
                Text("Search").tag(Segment.search)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if segment == .indexers {
                ProwlarrIndexersView(instance: instance)
            } else {
                ProwlarrSearchView(instance: instance)
            }
        }
    }
}

/// Torznab/Newznab search for a Jackett or NZBHydra2 instance. These expose only
/// the Torznab feed by API key (rich management needs the admin login), so this
/// is a free-text search across the indexer's results.
private struct TorznabView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore
    @Environment(\.openURL) private var openURL

    @State private var term = ""
    @State private var results: [TorznabClient.Result] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var caps: TorznabClient.Capabilities?
    @State private var status: String?

    private var client: TorznabClient? { instanceStore.torznabClient(for: instance) }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search indexers", text: $term) { Task { await search() } }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }.tintedCards()
                } else if didSearch && results.isEmpty {
                    Text("No results.").foregroundStyle(.secondary).tintedCards()
                } else if !didSearch {
                    VStack(alignment: .leading, spacing: 6) {
                        if let caps {
                            Label("\(caps.serverTitle ?? instance.name) · \(caps.categoryCount) categories",
                                  systemImage: "checkmark.seal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Type above to search this indexer for any release.")
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    .tintedCards()
                }
                ForEach(results) { result in
                    TorznabResultRow(result: result) { open(result) }
                }
                .tintedCards()
            }
        }
        .task { caps = try? await client?.capabilities() }
        .overlay(alignment: .bottom) { Toast(message: status) { status = nil } }
    }

    private func search() async {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let client else { return }
        isSearching = true
        didSearch = true
        defer { isSearching = false }
        results = ((try? await client.search(query: trimmed)) ?? [])
            .sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
    }

    private func open(_ result: TorznabClient.Result) {
        guard let link = result.link, let url = URL(string: link) else {
            status = "No download link available."
            return
        }
        openURL(url)
    }
}

private struct TorznabResultRow: View {
    let result: TorznabClient.Result
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.title ?? "Untitled").font(.subheadline).lineLimit(2)
            HStack(spacing: 14) {
                Label(Format.bytes(result.size), systemImage: "internaldrive")
                if let seeders = result.seeders { Label("\(seeders)", systemImage: "arrow.up") }
                if let indexer = result.indexer { Text(indexer).lineLimit(1) }
                Spacer()
                Button { onOpen() } label: { Label("Open", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(result.link == nil)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
