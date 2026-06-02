import SwiftUI
import NautilarrCore

/// A rich list-style library card: poster, title, provider/year, completion,
/// overview, genres and status pills. Used in the Library's list view mode.
struct MediaListRow: View {
    let entry: MediaEntry
    @EnvironmentObject private var instanceStore: InstanceStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            poster
                .frame(width: 84, height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.headline).lineLimit(1)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Label(entry.detail, systemImage: entry.kind.symbol)
                    .font(.caption).foregroundStyle(.secondary)
                if let overview = entry.overview, !overview.isEmpty {
                    Text(overview).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                pills
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Metrics.cardPadding)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius))
    }

    private var pills: some View {
        HStack(spacing: 6) {
            StatusBadge(text: entry.isComplete ? "Complete" : "Incomplete",
                        color: entry.isComplete ? .green : .orange)
            if let status = entry.statusText {
                StatusBadge(text: status, color: .secondary)
            }
            if entry.isMonitored {
                Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.teal)
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = PosterURL.resolve(entry.posterURLString, instance: entry.instance) {
            AsyncCachedImage(
                url: url,
                headers: instanceStore.imageHeaders(for: entry.instance),
                allowSelfSignedHosts: entry.instance.allowSelfSignedCertificates
                    ? Set(entry.instance.candidateBaseURLs().compactMap { $0.host }) : []
            )
        } else {
            ZStack { Theme.backgroundGradient; Image(systemName: entry.kind.symbol).foregroundStyle(.white.opacity(0.6)) }
        }
    }
}
