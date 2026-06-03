import SwiftUI
import NautilarrCore

/// Download-queue preferences: enable/disable individual download clients and
/// the client-side seed limit (by days and/or ratio).
struct DownloadsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var instanceStore: InstanceStore

    private static let clientTypes: [ServiceType] = [.qbittorrent, .transmission, .deluge, .sabnzbd, .nzbget]
    private var clients: [ServiceInstance] {
        instanceStore.instancesInActiveNetwork.filter { Self.clientTypes.contains($0.type) }
    }

    private var arrInstances: [ServiceInstance] {
        instanceStore.instancesInActiveNetwork.filter { $0.type == .sonarr || $0.type == .radarr }
    }

    var body: some View {
        Form {
            if !arrInstances.isEmpty {
                Section {
                    NavigationLink {
                        ArrDownloadClientsView().appBackground(settings.background)
                    } label: {
                        Label("Sonarr / Radarr download clients", systemImage: "externaldrive.connected.to.line.below")
                    }
                } footer: {
                    Text("Enable or disable the download clients configured inside each Sonarr and Radarr instance, and test them.")
                }
                .tintedCards()
            }

            if !clients.isEmpty {
                Section {
                    ForEach(clients) { client in
                        Toggle(isOn: Binding(
                            get: { settings.isClientEnabled(client.id) },
                            set: { settings.setClientEnabled(client.id, $0) }
                        )) {
                            HStack(spacing: 10) {
                                ServiceIcon(type: client.type, size: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(client.name)
                                    Text(client.type.displayName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Download clients")
                } footer: {
                    Text("Turn a client off to exclude it from the unified queue and stop polling it. It stays configured and can be turned back on here.")
                }
                .tintedCards()
            }

            Section {
                Toggle("Limit seeding", isOn: Binding(
                    get: { settings.seedLimitEnabled },
                    set: { settings.seedLimitEnabled = $0 }
                ))
                if settings.seedLimitEnabled {
                    Toggle("By days", isOn: Binding(
                        get: { settings.seedLimitByDays },
                        set: { settings.seedLimitByDays = $0 }
                    ))
                    if settings.seedLimitByDays {
                        Stepper(value: Binding(
                            get: { settings.maxSeedDays },
                            set: { settings.maxSeedDays = $0 }
                        ), in: 1...365) {
                            LabeledContent("Maximum days", value: "\(settings.maxSeedDays)")
                        }
                    }
                    Toggle("By ratio", isOn: Binding(
                        get: { settings.seedLimitByRatio },
                        set: { settings.seedLimitByRatio = $0 }
                    ))
                    if settings.seedLimitByRatio {
                        Stepper(value: Binding(
                            get: { settings.maxSeedRatio },
                            set: { settings.maxSeedRatio = $0 }
                        ), in: 0.25...100, step: 0.25) {
                            LabeledContent("Maximum ratio", value: String(format: "%.2f", settings.maxSeedRatio))
                        }
                    }
                    Picker("When exceeded", selection: Binding(
                        get: { settings.seedLimitAction },
                        set: { settings.seedLimitAction = $0 }
                    )) {
                        ForEach(SeedLimitAction.allCases) { action in
                            Label(action.label, systemImage: action.symbol).tag(action)
                        }
                    }
                }
            } header: {
                Text("Seed limit")
            } footer: {
                Text("Applies to torrent clients (qBittorrent, Transmission, Deluge). When a torrent passes the day and/or ratio limit, Nautilarr runs the chosen action while the Downloads screen is open. Usenet downloads don't seed and are never affected.")
            }
            .tintedCards()
        }
        .navigationTitle("Downloads")
    }
}
