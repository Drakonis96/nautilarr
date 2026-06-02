import SwiftUI
import NautilarrCore

/// Networking timeouts, streaming refresh, and maintenance actions.
struct AdvancedSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var clearedMessage: String?

    var body: some View {
        Form {
            Section("Networking") {
                Stepper(value: Binding(get: { settings.httpTimeout }, set: { settings.httpTimeout = $0 }),
                        in: 5...300, step: 5) {
                    HStack { Text("HTTP Timeout"); Spacer(); Text("\(settings.httpTimeout)s").foregroundStyle(.secondary) }
                }
                Stepper(value: Binding(get: { settings.sshTimeout }, set: { settings.sshTimeout = $0 }),
                        in: 5...120, step: 5) {
                    HStack { Text("SSH Timeout"); Spacer(); Text("\(settings.sshTimeout)s").foregroundStyle(.secondary) }
                }
            }

            Section {
                Toggle("Auto-Refresh Now Playing", isOn: Binding(
                    get: { settings.autoRefreshNowPlaying }, set: { settings.autoRefreshNowPlaying = $0 }
                ))
            } header: {
                Text("Streaming")
            } footer: {
                Text("Refreshes Tautulli activity on the dashboard every 10 seconds while open.")
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await ImageCache.shared.clear()
                        clearedMessage = "Image cache cleared."
                    }
                } label: {
                    Label("Clear Image Cache", systemImage: "trash")
                }
                if let clearedMessage {
                    Text(clearedMessage).font(.caption).foregroundStyle(.green)
                }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("Deletes cached posters and artwork. Use this if images look stale.")
            }

            Section {
                LabeledContent("Secret storage") {
                    Label(instanceStore.secretsUseKeychain ? "Keychain" : "On-device file",
                          systemImage: instanceStore.secretsUseKeychain ? "key.fill" : "doc.fill")
                        .foregroundStyle(instanceStore.secretsUseKeychain ? .green : .orange)
                }
            } footer: {
                Text(instanceStore.secretsUseKeychain
                     ? "API keys and passwords are stored in the system Keychain."
                     : "The Keychain is unavailable in this build (e.g. an unsigned/ad-hoc Mac app), so secrets are stored in the app's on-device container instead.")
            }
        }
        .navigationTitle("Advanced")
    }
}
