import SwiftUI
import NautilarrCore

/// A compact menu for switching the active network — shown in the Home toolbar.
struct NetworkSwitcher: View {
    @EnvironmentObject private var store: InstanceStore

    var body: some View {
        Menu {
            Picker("Network", selection: Binding(
                get: { store.activeNetworkID },
                set: { store.selectNetwork($0) }
            )) {
                ForEach(store.networks) { network in Text(network.name).tag(network.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(store.activeNetwork?.name ?? "Network").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
    }
}

/// Manage network profiles: switch the active one, add, rename and delete.
struct NetworksSettingsView: View {
    @EnvironmentObject private var store: InstanceStore
    @State private var newName = ""
    @State private var renaming: ServiceNetwork?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                ForEach(store.networks) { network in
                    Button {
                        store.selectNetwork(network.id)
                    } label: {
                        HStack {
                            Image(systemName: "globe").foregroundStyle(Theme.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(network.name).foregroundStyle(.primary)
                                Text("\(serviceCount(network.id)) service(s)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if network.id == store.activeNetworkID {
                                Image(systemName: "checkmark").foregroundStyle(Theme.teal)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if store.networks.count > 1 {
                            Button(role: .destructive) { store.deleteNetwork(network.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        Button { renaming = network; renameText = network.name } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                Text("Networks")
            } footer: {
                Text("Each network is a separate set of services — e.g. one for home and one for a remote/proxied setup. Switching changes everything the app shows.")
            }

            Section("Add network") {
                HStack {
                    TextField("Name", text: $newName)
                    Button("Add") {
                        let trimmed = newName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        store.addNetwork(named: trimmed)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Networks")
        .alert("Rename Network", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameNetwork(renaming.id, to: renameText.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
        }
    }

    private func serviceCount(_ id: UUID) -> Int {
        store.instances.filter { $0.networkID == id }.count
    }
}
