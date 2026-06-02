import SwiftUI
import NautilarrCore
import ProwlarrKit

/// Manage a Prowlarr instance's indexers — enable/disable each and test
/// connectivity.
struct ProwlarrIndexersView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore

    @State private var indexers: [ProwlarrIndexer] = []
    @State private var isLoading = false
    @State private var testing: Set<Int> = []
    @State private var status: String?

    var body: some View {
        List {
            if indexers.isEmpty && !isLoading {
                Text("No indexers configured.").foregroundStyle(.secondary)
            }
            ForEach(indexers) { indexer in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(indexer.name ?? "Indexer").font(.subheadline)
                        HStack(spacing: 6) {
                            if let proto = indexer.protocolName { Text(proto.capitalized) }
                            if let privacy = indexer.privacy { Text(privacy.capitalized) }
                            if let priority = indexer.priority { Text("Priority \(priority)") }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if testing.contains(indexer.id) {
                        ProgressView()
                    } else {
                        Button { Task { await test(indexer) } } label: {
                            Image(systemName: "stethoscope")
                        }
                        .buttonStyle(.borderless)
                    }
                    Toggle("", isOn: Binding(
                        get: { indexer.enable ?? false },
                        set: { value in Task { await setEnabled(indexer, value) } }
                    ))
                    .labelsHidden()
                }
            }
        }
        .navigationTitle("Indexers")
        .overlay { if isLoading && indexers.isEmpty { ProgressView() } }
        .overlay(alignment: .bottom) { Toast(message: status) { status = nil } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let client = instanceStore.prowlarrClient(for: instance) else { return }
        isLoading = true
        defer { isLoading = false }
        indexers = ((try? await client.indexers()) ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func setEnabled(_ indexer: ProwlarrIndexer, _ enabled: Bool) async {
        guard let client = instanceStore.prowlarrClient(for: instance) else { return }
        do {
            try await client.setIndexerEnabled(id: indexer.id, enabled: enabled)
            status = "\(enabled ? "Enabled" : "Disabled") \(indexer.name ?? "indexer")."
            await load()
        } catch {
            status = describe(error)
            await load()
        }
    }

    private func test(_ indexer: ProwlarrIndexer) async {
        guard let client = instanceStore.prowlarrClient(for: instance) else { return }
        testing.insert(indexer.id)
        defer { testing.remove(indexer.id) }
        do {
            try await client.testIndexer(id: indexer.id)
            status = "\(indexer.name ?? "Indexer") connected OK."
        } catch {
            status = "\(indexer.name ?? "Indexer") failed: \(describe(error))"
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
