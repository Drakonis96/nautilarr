import Foundation
import NautilarrCore

// MARK: - Models

/// `/api/system/status` payload (wrapped in `{ "data": … }`).
public struct BazarrSystemStatus: Codable, Sendable, Equatable {
    public var bazarrVersion: String?
    public var sonarrVersion: String?
    public var radarrVersion: String?
    public var operatingSystem: String?

    private enum CodingKeys: String, CodingKey {
        case bazarrVersion = "bazarr_version"
        case sonarrVersion = "sonarr_version"
        case radarrVersion = "radarr_version"
        case operatingSystem = "operating_system"
    }
}

private struct BazarrStatusEnvelope: Codable, Sendable { let data: BazarrSystemStatus }

/// `/api/badges` — counts surfaced in the UI badges.
public struct BazarrBadges: Codable, Sendable, Equatable {
    /// Episodes missing subtitles.
    public var episodes: Int?
    /// Movies missing subtitles.
    public var movies: Int?
    public var providers: Int?
    public var status: Int?
}

/// A subtitle language a Bazarr item is still missing.
public struct BazarrSubtitleLanguage: Codable, Sendable, Equatable, Hashable {
    public var name: String?
    public var code2: String?
    public var hi: Bool?
    public var forced: Bool?
}

/// An episode that is missing one or more subtitle languages (`/api/episodes/wanted`).
public struct BazarrWantedEpisode: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int { sonarrEpisodeId ?? 0 }
    public var seriesTitle: String?
    public var episodeTitle: String?
    public var episodeNumber: String?
    public var sonarrSeriesId: Int?
    public var sonarrEpisodeId: Int?
    public var missingSubtitles: [BazarrSubtitleLanguage]?

    private enum CodingKeys: String, CodingKey {
        case seriesTitle, episodeTitle
        case episodeNumber = "episode_number"
        case sonarrSeriesId, sonarrEpisodeId
        case missingSubtitles = "missing_subtitles"
    }
}

/// A movie that is missing one or more subtitle languages (`/api/movies/wanted`).
public struct BazarrWantedMovie: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int { radarrId ?? 0 }
    public var title: String?
    public var radarrId: Int?
    public var missingSubtitles: [BazarrSubtitleLanguage]?

    private enum CodingKeys: String, CodingKey {
        case title, radarrId
        case missingSubtitles = "missing_subtitles"
    }
}

private struct BazarrWantedEnvelope<Item: Codable & Sendable>: Codable, Sendable {
    let data: [Item]
    let total: Int?
}

/// A subtitle language configured in Bazarr (`/api/system/languages`).
public struct BazarrLanguage: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { code2 ?? code3 ?? name ?? "?" }
    public var name: String?
    public var code2: String?
    public var code3: String?
    public var enabled: Bool?
}

/// One candidate subtitle returned by a manual provider search
/// (`/api/providers/episodes` / `/api/providers/movies`). Fields are lenient
/// because Bazarr's shape varies by version.
public struct BazarrSubtitleResult: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { [provider, language, subtitle, releaseInfo?.first].compactMap { $0 }.joined(separator: "-") }
    public var provider: String?
    public var language: String?
    public var subtitle: String?
    public var score: Double?
    public var releaseInfo: [String]?
    public var uploader: String?
    public var url: String?

    private enum CodingKeys: String, CodingKey {
        case provider, language, subtitle, score, uploader, url
        case releaseInfo = "release_info"
    }
}

// MARK: - Client

/// Client for the Bazarr API (subtitles). `X-Api-Key` header auth via
/// `ServiceClientFactory`.
///
/// API reference (public, official): https://wiki.bazarr.media / the in-app
/// `/api/swagger` spec.
public struct BazarrClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    /// Connection test + version.
    public func systemStatus() async throws -> BazarrSystemStatus {
        let envelope: BazarrStatusEnvelope = try await api.send(.get("api/system/status"))
        return envelope.data
    }

    /// Counts of items missing subtitles, providers and status warnings.
    public func badges() async throws -> BazarrBadges {
        try await api.send(.get("api/badges"))
    }

    /// Episodes still missing subtitles.
    // VERIFY: GET /api/episodes/wanted returns { data: [...], total }.
    public func wantedEpisodes(start: Int = 0, length: Int = 100) async throws -> [BazarrWantedEpisode] {
        let query = [
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "length", value: String(length))
        ]
        let envelope: BazarrWantedEnvelope<BazarrWantedEpisode> = try await api.send(.get("api/episodes/wanted", query: query))
        return envelope.data
    }

    /// Movies still missing subtitles.
    // VERIFY: GET /api/movies/wanted returns { data: [...], total }.
    public func wantedMovies(start: Int = 0, length: Int = 100) async throws -> [BazarrWantedMovie] {
        let query = [
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "length", value: String(length))
        ]
        let envelope: BazarrWantedEnvelope<BazarrWantedMovie> = try await api.send(.get("api/movies/wanted", query: query))
        return envelope.data
    }

    /// Every wanted episode, paged to the reported `total` so the full catalogue
    /// loads (not just the first page).
    public func allWantedEpisodes(pageSize: Int = 500, maxItems: Int = 8000) async throws -> [BazarrWantedEpisode] {
        var all: [BazarrWantedEpisode] = []
        var start = 0
        while all.count < maxItems {
            let env: BazarrWantedEnvelope<BazarrWantedEpisode> = try await api.send(.get("api/episodes/wanted", query: [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "length", value: String(pageSize))
            ]))
            all += env.data
            if env.data.count < pageSize { break }
            if let total = env.total, all.count >= total { break }
            start += pageSize
        }
        return all
    }

    /// Every wanted movie, paged to the reported `total`.
    public func allWantedMovies(pageSize: Int = 500, maxItems: Int = 8000) async throws -> [BazarrWantedMovie] {
        var all: [BazarrWantedMovie] = []
        var start = 0
        while all.count < maxItems {
            let env: BazarrWantedEnvelope<BazarrWantedMovie> = try await api.send(.get("api/movies/wanted", query: [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "length", value: String(pageSize))
            ]))
            all += env.data
            if env.data.count < pageSize { break }
            if let total = env.total, all.count >= total { break }
            start += pageSize
        }
        return all
    }

    /// Configured subtitle languages (defaults to only the enabled ones).
    // VERIFY: GET /api/system/languages?enabled=true.
    public func languages(onlyEnabled: Bool = true) async throws -> [BazarrLanguage] {
        let query = onlyEnabled ? [URLQueryItem(name: "enabled", value: "true")] : []
        return try await api.send(.get("api/system/languages", query: query))
    }

    /// Manual provider search for an episode's subtitles.
    // VERIFY: GET /api/providers/episodes?episodeid= returns results (bare array or { data }).
    public func episodeSubtitleResults(episodeId: Int) async throws -> [BazarrSubtitleResult] {
        let data = try await api.sendReturningData(.get("api/providers/episodes", query: [URLQueryItem(name: "episodeid", value: String(episodeId))]))
        return Self.decodeResults(data)
    }

    /// Manual provider search for a movie's subtitles.
    // VERIFY: GET /api/providers/movies?radarrid= returns results (bare array or { data }).
    public func movieSubtitleResults(radarrId: Int) async throws -> [BazarrSubtitleResult] {
        let data = try await api.sendReturningData(.get("api/providers/movies", query: [URLQueryItem(name: "radarrid", value: String(radarrId))]))
        return Self.decodeResults(data)
    }

    /// Downloads a chosen subtitle for an episode.
    // VERIFY: POST /api/providers/episodes (form) — confirm field names against your Bazarr.
    public func downloadEpisodeSubtitle(seriesId: Int, episodeId: Int, language: String, provider: String, subtitle: String, hi: Bool = false, forced: Bool = false) async throws {
        let fields = [
            "seriesid": String(seriesId), "episodeid": String(episodeId),
            "language": language, "hi": String(hi), "forced": String(forced),
            "provider": provider, "subtitle": subtitle, "original_format": "false"
        ]
        try await api.send(Endpoint.form("api/providers/episodes", method: .post, fields: fields))
    }

    /// Downloads a chosen subtitle for a movie.
    // VERIFY: POST /api/providers/movies (form).
    public func downloadMovieSubtitle(radarrId: Int, language: String, provider: String, subtitle: String, hi: Bool = false, forced: Bool = false) async throws {
        let fields = [
            "radarrid": String(radarrId),
            "language": language, "hi": String(hi), "forced": String(forced),
            "provider": provider, "subtitle": subtitle, "original_format": "false"
        ]
        try await api.send(Endpoint.form("api/providers/movies", method: .post, fields: fields))
    }

    private static func decodeResults(_ data: Data) -> [BazarrSubtitleResult] {
        let decoder = JSONDecoder.nautilarr
        if let env = try? decoder.decode(BazarrWantedEnvelope<BazarrSubtitleResult>.self, from: data) { return env.data }
        if let arr = try? decoder.decode([BazarrSubtitleResult].self, from: data) { return arr }
        return []
    }
}
