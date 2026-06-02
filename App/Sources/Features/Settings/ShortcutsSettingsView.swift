import SwiftUI

/// Configure Plex / Jellyfin quick-link sections. Each can open a web/IP address
/// we enter, or the native app via its URL scheme. Enabled shortcuts appear as
/// their own navigation sections and can be reordered in Appearance.
struct ShortcutsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            ForEach(MediaShortcut.allCases) { kind in
                section(for: kind)
            }
        }
        .navigationTitle("Shortcuts")
    }

    @ViewBuilder
    private func section(for kind: MediaShortcut) -> some View {
        let enabled = Binding(
            get: { settings.shortcutEnabled(kind) },
            set: { settings.setShortcutEnabled(kind, $0) }
        )
        let usesApp = Binding(
            get: { settings.shortcutUsesApp(kind) },
            set: { settings.setShortcutUsesApp(kind, $0) }
        )

        Section {
            Toggle(isOn: enabled) {
                HStack(spacing: 10) {
                    Image(kind.logoAssetName)
                        .resizable().scaledToFit()
                        .frame(width: 24, height: 24)
                    Text("Show \(kind.displayName) shortcut")
                }
            }

            if enabled.wrappedValue {
                Picker("Open", selection: usesApp) {
                    Text("Web / IP").tag(false)
                    Text("Native app").tag(true)
                }
                .pickerStyle(.segmented)

                TextField("https://… or 192.168.x.x:port", text: Binding(
                    get: { settings.shortcutWeb(kind) },
                    set: { settings.setShortcutWeb(kind, $0) }
                ))
                .textInputAutocapitalizationCompat()
                .autocorrectionDisabled()

                if usesApp.wrappedValue {
                    TextField("App URL scheme (e.g. \(kind.defaultAppScheme))", text: Binding(
                        get: { settings.shortcutApp(kind) },
                        set: { settings.setShortcutApp(kind, $0) }
                    ))
                    .textInputAutocapitalizationCompat()
                    .autocorrectionDisabled()
                }
            }
        } header: {
            Text(kind.displayName)
        } footer: {
            if enabled.wrappedValue {
                Text(usesApp.wrappedValue
                     ? "Launches the installed \(kind.displayName) app via its URL scheme. If no app handles it (e.g. Jellyfin Media Player on Mac), Nautilarr opens the web address instead — so set both."
                     : "Opens this address in your browser. Use your server's web UI or LAN IP and port.")
            } else {
                Text("Adds a \(kind.displayName) section to the sidebar / tab bar.")
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func textInputAutocapitalizationCompat() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
