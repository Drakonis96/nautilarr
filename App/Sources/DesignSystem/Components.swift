import SwiftUI
import NautilarrCore
import SonarrKit

/// A rounded surface used to group dashboard content.
struct CardContainer<Content: View>: View {
    var title: LocalizedStringKey?
    var systemImage: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(.primary)
            }
            content()
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }
}

/// A small coloured pill for statuses / health severities.
struct StatusBadge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

extension SonarrHealthItem.Severity {
    var color: Color {
        switch self {
        case .ok: return .green
        case .notice: return .blue
        case .warning: return .orange
        case .error: return .red
        case .unknown: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .notice: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Full-screen biometric lock placeholder with an Unlock button.
struct BiometricLockView: View {
    let reason: String
    let authenticate: () async -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "faceid").font(.system(size: 52)).foregroundStyle(.white)
                Text(reason).font(.headline).foregroundStyle(.white)
                Button("Unlock") { Task { await authenticate() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Theme.navy)
            }
        }
    }
}

/// App-wide privacy lock: a frosted veil (paired with a blur on the app behind
/// it) that hides every bit of content, showing only a large app logo and the
/// Face ID glyph. Used when the app is locked by Face ID so nothing sensitive is
/// visible until the user authenticates.
struct PrivacyLockView: View {
    let reason: LocalizedStringKey
    let authenticate: () async -> Void

    var body: some View {
        ZStack {
            // The frosted layer over the (already blurred) app — together these
            // make the underlying content unreadable.
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Rectangle().fill(Theme.navy.opacity(0.25)).ignoresSafeArea()

            VStack(spacing: 22) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .shadow(color: Theme.teal.opacity(0.5), radius: 16, y: 6)
                Image(systemName: "faceid")
                    .font(.system(size: 52))
                    .foregroundStyle(.primary)
                Button {
                    Task { await authenticate() }
                } label: {
                    Label(reason, systemImage: "lock.open.fill")
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

/// A persistent inline error banner (e.g. for failed loads).
struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A transient status message shown at the bottom of a screen, auto-dismissing.
struct Toast: View {
    let message: String?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { onDismiss() }
                }
        }
    }
}

/// A release row reused by the movie/album interactive-search lists.
struct ReleaseRowGeneric: View {
    let title: String
    var quality: String?
    var indexer: String?
    var rejected: Bool
    var size: Int64?
    var seeders: Int?
    var leechers: Int?
    let onGrab: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).lineLimit(2)
            HStack(spacing: 10) {
                if let quality { StatusBadge(text: quality, color: Theme.teal) }
                if let indexer { StatusBadge(text: indexer) }
                if rejected { StatusBadge(text: "Rejected", color: .orange) }
            }
            HStack(spacing: 14) {
                Label(Format.bytes(size), systemImage: "internaldrive")
                if let seeders { Label("\(seeders)", systemImage: "arrow.up") }
                if let leechers { Label("\(leechers)", systemImage: "arrow.down") }
                Spacer()
                Button("Grab", action: onGrab).buttonStyle(.borderedProminent).controlSize(.small)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// A secure text field with an eye button to reveal/hide what's typed — so the
/// user can double-check a password they're entering.
struct RevealableSecureField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(prompt, text: $text)
                } else {
                    SecureField(prompt, text: $text)
                }
            }
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "Hide password" : "Show password")
        }
    }
}

/// A sheet that prompts for a passphrase with a reveal toggle and confirm/cancel
/// actions. Used for encrypting/decrypting configuration backups.
struct PassphrasePromptView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    @Binding var passphrase: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RevealableSecureField(prompt: "Password", text: $passphrase)
                } footer: {
                    Text(message)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) { onConfirm() }
                        .disabled(passphrase.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// A prominent in-content search field. Used where a system `.searchable` bar
/// would render twice — e.g. a `NavigationSplitView` detail root on Mac Catalyst,
/// which placed one (working) bar in the toolbar and a second (dead) one in the
/// content. This is a single, reliable field placed where the user expects it.
struct SearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            // The magnifier doubles as a tappable search button, so the search
            // can be triggered without a hardware return key (e.g. on Mac).
            Button(action: onSubmit) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .glassChip()
        .overlay(Capsule().strokeBorder(Color.hairline.opacity(0.6)))
    }
}

/// A compact glass segmented control where only the **selected** segment shows
/// its label; the others are icon-only. Ideal for bars with many segments (where
/// a stock `.segmented` Picker truncates the labels). Uses Liquid Glass.
struct GlassSegmentedBar<Tag: Hashable & Identifiable>: View {
    let tags: [Tag]
    let title: (Tag) -> LocalizedStringKey
    let systemImage: (Tag) -> String
    @Binding var selection: Tag

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags) { tag in
                let isSelected = tag == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = tag }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage(tag))
                        if isSelected { Text(title(tag)).lineLimit(1).fixedSize() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, isSelected ? 14 : 11)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .background { if isSelected { Capsule().fill(Color.accentColor) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(tag))
            }
        }
        .padding(4)
        .glassChip()
        .overlay(Capsule().strokeBorder(Color.hairline.opacity(0.5)))
    }
}

extension View {
    /// Adds a trailing toolbar "done" control rendered as a checkmark icon
    /// (top-right), the standard place to dismiss a sheet. Replaces the old
    /// leading "Done" text button so every sheet dismisses consistently.
    func doneToolbar(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: action) {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Done")
            }
        }
    }
}

// MARK: - Linked file metadata

/// A service-neutral view of a downloaded file's technical details, built by the
/// movie/episode detail screens from their Radarr/Sonarr file models.
struct FileMetadata {
    var quality: String?
    var resolution: String?
    var videoCodec: String?
    var dynamicRange: String?
    var audioCodec: String?
    var audioChannels: Double?
    var audioLanguages: String?
    var subtitles: String?
    var languages: String?
    var size: Int64?
    var runtime: String?

    var hasAny: Bool {
        [quality, resolution, videoCodec, audioCodec, audioLanguages, languages].contains { ($0?.isEmpty == false) } || size != nil
    }
}

/// Rows describing a linked file, for use inside a `Section`.
struct FileInfoRows: View {
    let meta: FileMetadata

    var body: some View {
        if let q = meta.quality, !q.isEmpty { LabeledContent("Quality", value: q) }
        if let r = meta.resolution, !r.isEmpty { LabeledContent("Resolution", value: r) }
        if let v = video { LabeledContent("Video", value: v) }
        if let a = audio { LabeledContent("Audio", value: a) }
        if let langs = languages { LabeledContent("Audio Languages", value: langs) }
        if let subs = meta.subtitles, !subs.isEmpty { LabeledContent("Subtitles", value: pretty(subs)) }
        if let size = meta.size, size > 0 { LabeledContent("File Size", value: Format.bytes(size)) }
    }

    private var video: String? {
        let parts = [meta.videoCodec, meta.dynamicRange].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var audio: String? {
        let ch = meta.audioChannels.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
        let parts = [meta.audioCodec, ch].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    private var languages: String? {
        guard let l = meta.audioLanguages ?? meta.languages, !l.isEmpty else { return nil }
        return pretty(l)
    }
    private func pretty(_ s: String) -> String {
        s.split(whereSeparator: { $0 == "/" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Release sorting

/// Sort order for interactive search (release) lists.
enum ReleaseSort: String, CaseIterable, Identifiable {
    case seeders, size, quality, leechers, title
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .seeders: return "Seeders"
        case .size: return "Size"
        case .quality: return "Quality"
        case .leechers: return "Leechers"
        case .title: return "Title"
        }
    }
}

/// Formatting helpers shared across screens.
enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bytes(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// A compact watch-time string from a number of seconds (e.g. "3h 12m").
    static func duration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(seconds)s"
    }
}

/// A toolbar refresh button: an arrow that spins continuously while loading.
/// Tapping it triggers `action`; it's disabled while already loading.
struct RefreshSpinnerButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(isLoading ? 360 : 0))
                .animation(isLoading
                           ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                           : .default,
                           value: isLoading)
        }
        .disabled(isLoading)
        .accessibilityLabel(Text("Refresh"))
    }
}
