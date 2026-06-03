import SwiftUI
import CoreImage
import UIKit
import NautilarrCore
import OverseerrKit

// MARK: - Header data

/// One rating chip (IMDb / TMDB / Rotten Tomatoes / …).
struct DetailRating: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let color: Color
    /// SF Symbol fallback when no brand logo is supplied.
    let systemImage: String?
    /// Bundled brand logo (vector PDF imageset), preferred over `systemImage`.
    var assetName: String? = nil
}

/// Everything the rich detail header needs, built by the movie/series views.
struct DetailHeaderData {
    let instance: ServiceInstance
    let posterURL: String?
    let fanartURL: String?
    let title: String
    let year: Int?
    let runtime: Int?
    let certification: String?
    let status: String?
    let statusColor: Color
    let genres: [String]
    let ratings: [DetailRating]
    let metaLine: String?
    let sizeText: String?
}

// MARK: - Header

/// A cinematic detail header: a fanart backdrop tinted with a colour sampled from
/// the poster, the poster itself, title, runtime/certification, rating chips and
/// genres. Designed to sit at the top of a `List` with cleared row insets.
struct MediaDetailHeader: View {
    let data: DetailHeaderData
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var accent: Color = Theme.navy

    private let backdropHeight: CGFloat = 196
    private let posterOverlap: CGFloat = 58
    private let posterW: CGFloat = 118
    private let posterH: CGFloat = 176

    var body: some View {
        // A backdrop band on top, then the poster + info below — the poster
        // overlaps the band but stays fully inside the horizontal margins, so it
        // is never clipped by the screen edge or a rounded section corner.
        VStack(alignment: .leading, spacing: 0) {
            backdropBand
            infoRow
        }
        .task(id: data.posterURL) { await loadAccent() }
    }

    private var backdropBand: some View {
        ZStack(alignment: .bottom) {
            backdrop
            scrim
        }
        .frame(maxWidth: .infinity)
        .frame(height: backdropHeight)
        .clipped()
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = resolve(data.fanartURL) {
            AsyncCachedImage(url: url, headers: headers, allowSelfSignedHosts: hosts)
                .frame(maxWidth: .infinity)
                .frame(height: backdropHeight)
                .clipped()
        } else {
            LinearGradient(colors: [accent, accent.opacity(0.55), Theme.navy],
                           startPoint: .top, endPoint: .bottom)
                .frame(maxWidth: .infinity)
                .frame(height: backdropHeight)
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: accent.opacity(0.30), location: 0.55),
                .init(color: Color(uiColor: .systemBackground).opacity(0.92), location: 0.9),
                .init(color: Color(uiColor: .systemBackground), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: backdropHeight)
    }

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 14) {
            posterView
                .frame(width: posterW, height: posterH)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18)))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 7) {
                Text(data.title)
                    .font(.title2.weight(.heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                metaLine
                if !data.ratings.isEmpty { ratingsRow }
                if !data.genres.isEmpty { genreChips }
            }
            .padding(.top, posterOverlap + 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, -posterOverlap)   // pull the poster up to overlap the band
        .padding(.bottom, 6)
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let year = data.year { Text(String(year)) }
            if let runtime = data.runtime, runtime > 0 { Text(runtimeText(runtime)) }
            if let cert = data.certification, !cert.isEmpty {
                Text(cert)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary))
            }
            if let status = data.status, !status.isEmpty {
                StatusBadge(text: status, color: data.statusColor)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    /// Rating chips. Each is fixed-size and the row scrolls horizontally, so the
    /// chips never get squished into illegible blobs when the column is narrow
    /// (e.g. a large Dynamic Type size next to the poster).
    private var ratingsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(data.ratings) { rating in
                    ratingChip(rating)
                }
            }
        }
    }

    private func ratingChip(_ rating: DetailRating) -> some View {
        HStack(spacing: 4) {
            if let asset = rating.assetName {
                Image(asset)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else if let symbol = rating.systemImage {
                Image(systemName: symbol).font(.caption2)
            }
            Text(rating.value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(rating.color.opacity(0.20), in: Capsule())
        .foregroundStyle(rating.color)
        .fixedSize()
    }

    private var genreChips: some View {
        HStack(spacing: 6) {
            ForEach(data.genres.prefix(4), id: \.self) { genre in
                Text(genre)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var posterView: some View {
        if let url = resolve(data.posterURL) {
            AsyncCachedImage(url: url, headers: headers, allowSelfSignedHosts: hosts)
        } else {
            ZStack { Theme.backgroundGradient; Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.6)) }
        }
    }

    // MARK: Helpers

    private var headers: [String: String] { instanceStore.imageHeaders(for: data.instance) }
    private var hosts: Set<String> {
        data.instance.allowSelfSignedCertificates ? Set(data.instance.candidateBaseURLs().compactMap { $0.host }) : []
    }
    private func resolve(_ raw: String?) -> URL? { PosterURL.resolve(raw, instance: data.instance) }

    private func runtimeText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func loadAccent() async {
        guard let url = resolve(data.posterURL),
              let data = try? await ImageCache.shared.data(for: url, headers: headers, allowSelfSignedHosts: hosts),
              let image = PlatformImage(data: data),
              let color = MediaColor.dominant(image) else { return }
        await MainActor.run { withAnimation(.easeOut(duration: 0.5)) { accent = color } }
    }
}

// MARK: - Poster colour sampling

enum MediaColor {
    /// Average colour of an image, saturation-boosted for a livelier header tint.
    static func dominant(_ image: PlatformImage) -> Color? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        let params: [String: Any] = [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]
        guard let output = CIFilter(name: "CIAreaAverage", parameters: params)?.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        ctx.render(output, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let base = UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard base.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return Color(uiColor: base) }
        return Color(hue: Double(h), saturation: Double(min(1, s * 1.45)), brightness: Double(min(0.8, max(0.3, b))))
    }
}

// MARK: - Cast

/// Horizontal cast strip, sourced from Overseerr/Jellyseerr (TMDB credits) when a
/// requests service is configured. Renders nothing if unavailable.
struct MediaCastStrip: View {
    let mediaType: String   // "movie" | "tv"
    let tmdbId: Int?
    let title: String
    let year: Int?
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var cast: [OverseerrCastMember] = []
    @State private var loaded = false

    private var hasOverseerr: Bool { !instanceStore.instances(ofType: .overseerr).isEmpty }

    var body: some View {
        // The `.task` is hosted on this stable VStack — NOT on `content` — so the
        // in-flight Overseerr fetch isn't cancelled when `content` swaps from the
        // loading row to the cast card (which would otherwise abort the request).
        VStack(spacing: 0) { content }
            .task { if hasOverseerr { await loadIfNeeded() } }
    }

    @ViewBuilder
    private var content: some View {
        if !cast.isEmpty {
            CardContainer(title: "Cast", systemImage: "person.2.fill") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(cast.prefix(20)) { CastCard(member: $0) }
                    }
                    .padding(.horizontal, 2)
                }
            }
        } else if hasOverseerr && !loaded {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading cast…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let instance = instanceStore.instances(ofType: .overseerr).first,
              let client = instanceStore.overseerrClient(for: instance) else { return }
        // Prefer the real TMDB id (Radarr movies and most Sonarr series expose it).
        var id: Int? = (tmdbId ?? 0) > 0 ? tmdbId : nil
        if id == nil, let year {
            // Last resort: a year-constrained title search. Only accept a match
            // whose year agrees, so we never show the wrong cast.
            if let results = try? await client.search(query: title) {
                let want = mediaType == "tv" ? "tv" : "movie"
                id = results.first { $0.mediaType == want && $0.year == String(year) }?.id
            }
        }
        guard let id else { return }
        if let details = try? await client.mediaDetails(mediaType: mediaType, tmdbId: id) {
            cast = details.cast
        }
    }
}

private struct CastCard: View {
    let member: OverseerrCastMember

    private var url: URL? {
        guard let path = member.profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }

    var body: some View {
        VStack(spacing: 6) {
            AsyncCachedImage(url: url)
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            Text(member.name ?? "—").font(.caption2.weight(.semibold)).lineLimit(1)
            if let character = member.character, !character.isEmpty {
                Text(character).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 86)
    }
}
