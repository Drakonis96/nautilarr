import SwiftUI
import NautilarrCore
import UnraidKit

/// A read-only Unraid dashboard over the official GraphQL API: system info,
/// array status with capacity, and the Docker container list. (Container control
/// is available over SSH; the GraphQL mutations aren't integrated yet.)
struct UnraidDetailView: View {
    let instance: ServiceInstance
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings

    @State private var snapshot: UnraidSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var client: UnraidClient? { instanceStore.unraidClient(for: instance) }

    var body: some View {
        List {
            if let error = errorMessage {
                Section { ErrorBanner(message: error) }.tintedCards()
            }
            if let info = snapshot?.info {
                Section("System") {
                    if let os = info.os {
                        if let distro = os.distro { LabeledContent("OS", value: [distro, os.release].compactMap { $0 }.joined(separator: " ")) }
                        if let uptime = os.uptime { LabeledContent("Uptime", value: prettyUptime(uptime)) }
                    }
                    if let cpu = info.cpu {
                        if let brand = cpu.brand { LabeledContent("CPU", value: brand) }
                        if let cores = cpu.cores {
                            LabeledContent("Cores", value: "\(cores)\(cpu.threads.map { " · \($0) threads" } ?? "")")
                        }
                    }
                }
                .tintedCards()
            }

            if let array = snapshot?.array {
                Section("Array") {
                    HStack {
                        Text("Status")
                        Spacer()
                        StatusBadge(text: (array.state ?? "Unknown").capitalized,
                                    color: array.state?.uppercased() == "STARTED" ? .green : .orange)
                    }
                    if let disks = array.capacity?.disks, let used = kb(disks.used), let total = kb(disks.total), total > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(used), total: Double(total)).tint(Theme.teal)
                            Text("\(Format.bytes(used)) used · \(Format.bytes((kb(disks.free) ?? (total - used)))) free")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .tintedCards()
            }

            if let containers = snapshot?.dockerContainers, !containers.isEmpty {
                Section {
                    ForEach(containers) { container in
                        HStack(spacing: 10) {
                            Circle().fill(container.isRunning ? .green : .secondary).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(container.displayName).font(.subheadline)
                                if let status = container.status {
                                    Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if container.autoStart == true {
                                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.yellow)
                            }
                        }
                    }
                } header: {
                    Text("Docker — \(snapshot?.runningContainers ?? 0)/\(snapshot?.totalContainers ?? 0) running")
                } footer: {
                    Text("Start/stop containers from this host's SSH service (Docker tab).")
                }
                .tintedCards()
            }

            if snapshot == nil && !isLoading && errorMessage == nil {
                Text("No data.").foregroundStyle(.secondary).tintedCards()
            }
        }
        .navigationTitle(instance.name)
        .appBackground(settings.background)
        .overlay { if isLoading && snapshot == nil { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshSpinnerButton(isLoading: isLoading) { Task { await load() } }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.snapshot()
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Unraid array capacity values are strings in KiB; convert to bytes.
    private func kb(_ value: String?) -> Int64? {
        guard let value, let n = Int64(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        return n * 1024
    }

    /// Uptime arrives as an ISO date (boot time) or a number; show it compactly.
    private func prettyUptime(_ raw: String) -> String {
        if let date = ISO8601DateFormatter().date(from: raw) {
            let seconds = Int(Date().timeIntervalSince(date))
            let days = seconds / 86_400, hours = (seconds % 86_400) / 3600
            if days > 0 { return "\(days)d \(hours)h" }
            return "\(hours)h"
        }
        return raw
    }
}
