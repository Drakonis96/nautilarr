import SwiftUI
import NautilarrCore

/// A poster tile used across library grids and detail headers. Works for any
/// media kind via a `MediaEntry`.
struct PosterTile: View {
    let entry: MediaEntry
    var showsTitle: Bool = true
    @EnvironmentObject private var instanceStore: InstanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
                .aspectRatio(Theme.Metrics.posterAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if entry.isMonitored {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
            if showsTitle {
                Text(entry.title)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let url = PosterURL.resolve(entry.posterURLString, instance: entry.instance) {
            AsyncCachedImage(
                url: url,
                headers: instanceStore.imageHeaders(for: entry.instance),
                allowSelfSignedHosts: entry.instance.allowSelfSignedCertificates
                    ? Set(entry.instance.candidateBaseURLs().compactMap { $0.host })
                    : []
            )
        } else {
            ZStack {
                Theme.backgroundGradient
                Image(systemName: entry.kind.symbol).font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Resolves a possibly server-relative cover URL against an instance's host.
enum PosterURL {
    static func resolve(_ raw: String?, instance: ServiceInstance) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http"), let url = URL(string: raw) { return url }
        guard let base = instance.candidateBaseURLs().first else { return nil }
        return URL(string: raw, relativeTo: base)
    }
}
