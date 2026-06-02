import SwiftUI
import NautilarrCore
import ProwlarrKit

/// Manual search across a Prowlarr instance's indexers, with one-tap grab to the
/// configured download client.
struct ProwlarrSearchView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore

    @State private var term = ""
    @State private var results: [ProwlarrSearchResult] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Search indexers", text: $term) { Task { await search() } }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
            List {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .tintedCards()
                } else if didSearch && results.isEmpty {
                    Text("No results.").foregroundStyle(.secondary)
                        .tintedCards()
                } else if !didSearch {
                    Text("Type above to search your indexers for any release.")
                        .foregroundStyle(.secondary).font(.subheadline)
                        .tintedCards()
                }
                ForEach(results) { result in
                    ReleaseRowGeneric(
                        title: result.title ?? "Untitled",
                        quality: result.protocolName?.capitalized,
                        indexer: result.indexer,
                        rejected: false,
                        size: result.size,
                        seeders: result.seeders,
                        leechers: result.leechers
                    ) { Task { await grab(result) } }
                }
                .tintedCards()
            }
        }
        .navigationTitle(instance.name)
        .overlay(alignment: .bottom) { Toast(message: status) { status = nil } }
    }

    private func search() async {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let client = instanceStore.prowlarrClient(for: instance) else { return }
        isSearching = true
        didSearch = true
        defer { isSearching = false }
        results = ((try? await client.search(query: trimmed)) ?? [])
            .sorted { ($0.seeders ?? 0) > ($1.seeders ?? 0) }
    }

    private func grab(_ result: ProwlarrSearchResult) async {
        guard let client = instanceStore.prowlarrClient(for: instance) else { return }
        do {
            try await client.grab(result)
            status = "Sent to download client."
        } catch {
            status = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
