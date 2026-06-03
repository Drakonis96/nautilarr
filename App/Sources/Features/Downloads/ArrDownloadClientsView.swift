import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit

/// Enable or disable the download clients configured **inside** each Sonarr and
/// Radarr instance (their Settings → Download Clients), and test connectivity.
/// This is distinct from Nautilarr's own download-client services — it toggles
/// the clients *arr uses to grab releases.
struct ArrDownloadClientsView: View {
    @EnvironmentObject private var instanceStore: InstanceStore

    @State private var clients: [UUID: [ArrDownloadClient]] = [:]
    @State private var loading: Set<UUID> = []
    @State private var testing: Set<String> = []
    @State private var status: String?

    private var arrInstances: [ServiceInstance] {
        instanceStore.instancesInActiveNetwork.filter { $0.type == .sonarr || $0.type == .radarr }
    }

    var body: some View {
        List {
            if arrInstances.isEmpty {
                ContentUnavailableLabel(
                    "No Sonarr or Radarr",
                    systemImage: "externaldrive.badge.xmark",
                    description: "Add a Sonarr or Radarr service to manage its download clients."
                )
                .tintedCards()
            }
            ForEach(arrInstances) { instance in
                Section {
                    let list = clients[instance.id] ?? []
                    if loading.contains(instance.id) && list.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if list.isEmpty {
                        Text("No download clients configured.")
                            .foregroundStyle(.secondary).font(.subheadline)
                    } else {
                        ForEach(list) { client in
                            clientRow(instance: instance, client: client)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        ServiceIcon(type: instance.type, size: 18)
                        Text(instance.name)
                    }
                }
                .tintedCards()
            }
        }
        .navigationTitle("Download Clients")
        .overlay { if loading.count == arrInstances.count && clients.isEmpty && !arrInstances.isEmpty { ProgressView() } }
        .overlay(alignment: .bottom) { Toast(message: status) { status = nil } }
        .refreshable { await loadAll() }
        .task { await loadAll() }
    }

    @ViewBuilder
    private func clientRow(instance: ServiceInstance, client: ArrDownloadClient) -> some View {
        let key = "\(instance.id)-\(client.id)"
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name ?? client.implementation ?? "Client").font(.subheadline)
                HStack(spacing: 6) {
                    if let proto = client.protocolName { Text(proto.capitalized) }
                    if let impl = client.implementation, impl != (client.name ?? "") { Text(impl) }
                    if let priority = client.priority { Text("Priority \(priority)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if testing.contains(key) {
                ProgressView()
            } else {
                Button { Task { await test(instance, client) } } label: {
                    Image(systemName: "stethoscope")
                }
                .buttonStyle(.borderless)
            }
            Toggle("", isOn: Binding(
                get: { client.enable ?? false },
                set: { value in Task { await setEnabled(instance, client, value) } }
            ))
            .labelsHidden()
        }
    }

    // MARK: - Data

    private func loadAll() async {
        for instance in arrInstances { await load(instance) }
    }

    private func load(_ instance: ServiceInstance) async {
        loading.insert(instance.id)
        defer { loading.remove(instance.id) }
        let result = await fetchClients(instance)
        clients[instance.id] = result.sorted { ($0.priority ?? 0, $0.name ?? "") < ($1.priority ?? 0, $1.name ?? "") }
    }

    private func fetchClients(_ instance: ServiceInstance) async -> [ArrDownloadClient] {
        switch instance.type {
        case .sonarr:
            guard let client = instanceStore.sonarrClient(for: instance) else { return [] }
            return (try? await client.downloadClients()) ?? []
        case .radarr:
            guard let client = instanceStore.radarrClient(for: instance) else { return [] }
            return (try? await client.downloadClients()) ?? []
        default:
            return []
        }
    }

    private func setEnabled(_ instance: ServiceInstance, _ client: ArrDownloadClient, _ enabled: Bool) async {
        do {
            switch instance.type {
            case .sonarr:
                guard let c = instanceStore.sonarrClient(for: instance) else { return }
                try await c.setDownloadClientEnabled(id: client.id, enabled: enabled)
            case .radarr:
                guard let c = instanceStore.radarrClient(for: instance) else { return }
                try await c.setDownloadClientEnabled(id: client.id, enabled: enabled)
            default:
                return
            }
            status = "\(enabled ? "Enabled" : "Disabled") \(client.name ?? "client")."
        } catch {
            status = describe(error)
        }
        await load(instance)
    }

    private func test(_ instance: ServiceInstance, _ client: ArrDownloadClient) async {
        let key = "\(instance.id)-\(client.id)"
        testing.insert(key)
        defer { testing.remove(key) }
        do {
            switch instance.type {
            case .sonarr:
                guard let c = instanceStore.sonarrClient(for: instance) else { return }
                try await c.testDownloadClient(id: client.id)
            case .radarr:
                guard let c = instanceStore.radarrClient(for: instance) else { return }
                try await c.testDownloadClient(id: client.id)
            default:
                return
            }
            status = "\(client.name ?? "Client") connected OK."
        } catch {
            status = "\(client.name ?? "Client") failed: \(describe(error))"
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
