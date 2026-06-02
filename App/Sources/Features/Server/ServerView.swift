import SwiftUI
import NautilarrCore

/// Server tools hub. Phase 1 shows configured services and their reachability;
/// SSH terminal, SFTP browsing and host stats arrive in Phase 3. SSH is gated
/// behind a Mac Catalyst compatibility check at build time.
struct ServerView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @StateObject private var model = ServerViewModel()

    private var sshInstances: [ServiceInstance] { instanceStore.instances(ofType: .ssh) }

    var body: some View {
        List {
            if !sshInstances.isEmpty {
                Section("SSH & SFTP") {
                    ForEach(sshInstances) { instance in
                        NavigationLink {
                            SSHDetailView(instance: instance)
                        } label: {
                            HStack(spacing: 12) {
                                ServiceIcon(type: .ssh, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instance.name)
                                    Text("Live charts · Terminal · Host stats · Files")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .tintedCards()
            }

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
                            StatusBadge(text: "Phase \(instance.type.phase.rawValue)")
                        }
                    }
                }
            }
            .tintedCards()

            if sshInstances.isEmpty {
                Section {
                    Label("Live host charts (CPU · RAM · network)", systemImage: "chart.xyaxis.line")
                        .foregroundStyle(.secondary)
                } footer: {
                    sshAvailabilityFooter
                }
                .tintedCards()
            }
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

    private var sshAvailabilityFooter: some View {
        Text("SSH/SFTP use a pure-Swift client (SwiftNIO SSH) — no paid entitlements. Add an SSH service to get a terminal, host stats and a file browser.")
    }
}
