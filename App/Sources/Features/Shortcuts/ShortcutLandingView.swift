import SwiftUI

/// Landing screen for a configurable media-server shortcut (Plex / Jellyfin).
/// Shows the brand logo and opens the configured target — a web/IP URL we set,
/// or the native app via its URL scheme.
struct ShortcutLandingView: View {
    let kind: MediaShortcut
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL

    private var brand: Color { Color(hex: kind.brandColorHex) }
    private var target: URL? { settings.shortcutURL(kind) }

    /// Opens the target. In native-app mode, if the app's URL scheme isn't
    /// handled (e.g. Jellyfin Media Player on Mac registers none), fall back to
    /// the configured web address so the shortcut never just hangs.
    private func open(_ url: URL) {
        openURL(url) { accepted in
            guard !accepted, settings.shortcutUsesApp(kind) else { return }
            let web = settings.shortcutWeb(kind).trimmingCharacters(in: .whitespaces)
            guard !web.isEmpty else { return }
            let raw = web.contains("://") ? web : "http://\(web)"
            if let webURL = URL(string: raw) { openURL(webURL) }
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(kind.logoAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
                .shadow(color: brand.opacity(0.5), radius: 18, y: 8)

            Text(kind.displayName)
                .font(.system(size: 34, weight: .heavy, design: .rounded))

            if let target {
                Text(settings.shortcutUsesApp(kind)
                     ? "Opens the \(kind.displayName) app"
                     : target.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)

                Button {
                    open(target)
                } label: {
                    Label("Open \(kind.displayName)", systemImage: "arrow.up.forward.app.fill")
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(brand)

                if settings.shortcutUsesApp(kind) {
                    Text("If the app doesn't open, Nautilarr falls back to the web address below.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ContentUnavailableLabel(
                    "Not configured yet",
                    systemImage: "gearshape",
                    description: "Set a web address or app for \(kind.displayName) in Settings → Shortcuts."
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
