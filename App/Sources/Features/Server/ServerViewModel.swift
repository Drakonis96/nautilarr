import SwiftUI
import NautilarrCore
import ProwlarrKit
import BazarrKit
import TautulliKit
import JellystatKit
import UnraidKit
import TorznabKit

/// Loads at-a-glance monitoring summaries for the Phase 3 services.
@MainActor
final class ServerViewModel: ObservableObject {
    struct MonitorLine: Identifiable {
        let id = UUID()
        let instanceName: String
        let type: ServiceType
        let summary: String
        var warning: String?
    }

    @Published var lines: [MonitorLine] = []
    @Published var isLoading = false

    func load(store: InstanceStore) async {
        let prowlarr = store.instances(ofType: .prowlarr)
        let bazarr = store.instances(ofType: .bazarr)
        let tautulli = store.instances(ofType: .tautulli)
        let jellystat = store.instances(ofType: .jellystat)
        let unraid = store.instances(ofType: .unraid)
        let indexers = store.instances(ofType: .nzbhydra2) + store.instances(ofType: .jackett)
        guard !(prowlarr.isEmpty && bazarr.isEmpty && tautulli.isEmpty && jellystat.isEmpty && unraid.isEmpty && indexers.isEmpty) else {
            lines = []; return
        }

        if lines.isEmpty { isLoading = true }
        defer { isLoading = false }
        var collected: [MonitorLine] = []

        for instance in prowlarr {
            guard let client = store.prowlarrClient(for: instance) else { continue }
            if let indexers = try? await client.indexers() {
                let enabled = indexers.filter { $0.enable == true }.count
                let health = (try? await client.health())?.filter { $0.severity == .warning || $0.severity == .error } ?? []
                collected.append(MonitorLine(
                    instanceName: instance.name, type: .prowlarr,
                    summary: "\(enabled)/\(indexers.count) indexers enabled",
                    warning: health.first?.message
                ))
            }
        }
        for instance in bazarr {
            guard let client = store.bazarrClient(for: instance) else { continue }
            if let badges = try? await client.badges() {
                collected.append(MonitorLine(
                    instanceName: instance.name, type: .bazarr,
                    summary: "\(badges.episodes ?? 0) episodes · \(badges.movies ?? 0) movies missing subtitles"
                ))
            }
        }
        for instance in tautulli {
            guard let client = store.tautulliClient(for: instance) else { continue }
            if let activity = try? await client.activity() {
                collected.append(MonitorLine(
                    instanceName: instance.name, type: .tautulli,
                    summary: "\(activity.count) active stream(s)"
                ))
            }
        }
        for instance in jellystat {
            guard let client = store.jellystatClient(for: instance) else { continue }
            if let sessions = try? await client.sessions() {
                collected.append(MonitorLine(
                    instanceName: instance.name, type: .jellystat,
                    summary: "\(sessions.count) active stream(s)"
                ))
            }
        }
        for instance in unraid {
            guard let client = store.unraidClient(for: instance) else { continue }
            if let snapshot = try? await client.snapshot() {
                let cpu = snapshot.info?.cpu?.brand ?? "CPU"
                collected.append(MonitorLine(
                    instanceName: instance.name, type: .unraid,
                    summary: "Array \(snapshot.array?.state ?? "—") · \(snapshot.runningContainers)/\(snapshot.totalContainers) containers · \(cpu)"
                ))
            }
        }
        for instance in indexers {
            guard let client = store.torznabClient(for: instance) else { continue }
            if let caps = try? await client.capabilities() {
                collected.append(MonitorLine(
                    instanceName: instance.name, type: instance.type,
                    summary: "\(caps.serverTitle ?? "Reachable") · \(caps.categoryCount) categories"
                ))
            }
        }
        lines = collected
    }
}
