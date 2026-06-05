import SwiftUI
import NautilarrCore

/// Server overview: at-a-glance monitoring summaries and the full list of
/// configured services. Deep per-service tools (Tautulli, Jellystat, Unraid,
/// SSH) live in their own top-level sections.
struct ServerView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var model = ServerViewModel()

    var body: some View {
        List {
            if !model.lines.isEmpty {
                Section("Monitoring") {
                    ForEach(model.lines) { line in
                        HStack(spacing: 12) {
                            ServiceIcon(type: line.type, size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.summary).font(.subheadline)
                                if let warning = line.warning {
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                                }
                                Text(line.instanceName).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .tintedCards()
            }

            Section("Configured services") {
                if instanceStore.instancesInActiveNetwork.isEmpty {
                    Text("No services configured yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(instanceStore.instancesInActiveNetwork) { instance in
                        HStack {
                            ServiceIcon(type: instance.type, size: 24)
                            VStack(alignment: .leading) {
                                Text(instance.name)
                                Text(instance.type.category).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: instance.type.displayName, color: Theme.teal)
                        }
                    }
                }
            }
            .tintedCards()
        }
        .overlay { if model.isLoading && model.lines.isEmpty { ProgressView() } }
        .refreshable { await model.load(store: instanceStore) }
        .task { await model.load(store: instanceStore) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: model.isLoading) {
                    Task { await model.load(store: instanceStore) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nautilarrRefresh)) { _ in
            Task { await model.load(store: instanceStore) }
        }
    }
}
