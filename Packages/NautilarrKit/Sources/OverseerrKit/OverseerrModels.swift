import Foundation

/// `GET /api/v1/status` — connection test.
public struct OverseerrStatus: Codable, Sendable, Equatable {
    public var version: String?
    public var commitTag: String?
}

/// Request approval state.
public enum OverseerrRequestStatus: Int, Codable, Sendable {
    case pending = 1
    case approved = 2
    case declined = 3
    case unknown = 0

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = OverseerrRequestStatus(rawValue: raw) ?? .unknown
    }

    public var label: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .unknown: return "Unknown"
        }
    }
}

public struct OverseerrUser: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var displayName: String?
    public var username: String?
    public var email: String?

    public var name: String { displayName ?? username ?? email ?? "Unknown user" }
}

public struct OverseerrMedia: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var tmdbId: Int?
    public var tvdbId: Int?
    /// `movie` or `tv`.
    public var mediaType: String?
    /// Availability status (1 unknown … 5 available).
    public var status: Int?
}

/// A media request (`GET /api/v1/request`).
public struct OverseerrRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var status: OverseerrRequestStatus
    /// `movie` or `tv`.
    public var type: String?
    public var media: OverseerrMedia?
    public var requestedBy: OverseerrUser?
    public var createdAt: Date?

    public var mediaType: String { type ?? media?.mediaType ?? "movie" }
}

public struct OverseerrPageInfo: Codable, Sendable, Equatable {
    public var pages: Int?
    public var results: Int?
    public var page: Int?
}

public struct OverseerrRequestPage: Codable, Sendable {
    public var pageInfo: OverseerrPageInfo?
    public var results: [OverseerrRequest]
}

public struct OverseerrRequestCount: Codable, Sendable, Equatable {
    public var total: Int?
    public var pending: Int?
    public var approved: Int?
    public var declined: Int?
    public var available: Int?
    public var processing: Int?
}

/// A cast member from a title's credits (TMDB-sourced via Overseerr).
public struct OverseerrCastMember: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var character: String?
    public var profilePath: String?
}

public struct OverseerrCredits: Codable, Sendable, Equatable {
    public var cast: [OverseerrCastMember]?
}

/// Title/artwork details fetched per request to enrich the feed.
public struct OverseerrMediaDetails: Codable, Sendable, Equatable {
    public var title: String?      // movies
    public var name: String?       // tv
    public var posterPath: String?
    public var overview: String?
    public var numberOfSeasons: Int?
    public var seasons: [OverseerrSeason]?
    public var voteAverage: Double?
    public var runtime: Int?
    public var credits: OverseerrCredits?

    public var displayTitle: String { title ?? name ?? "Untitled" }
    public var cast: [OverseerrCastMember] { credits?.cast ?? [] }
}

/// A TV season as surfaced by Overseerr's media details.
public struct OverseerrSeason: Codable, Sendable, Equatable {
    public var id: Int?
    public var seasonNumber: Int?
    public var name: String?
    public var episodeCount: Int?
}

/// A configured Radarr/Sonarr server known to Overseerr
/// (`GET /api/v1/service/{radarr|sonarr}`).
public struct OverseerrServer: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var is4k: Bool?
    public var isDefault: Bool?
    public var activeProfileId: Int?
    public var activeDirectory: String?
    public var activeLanguageProfileId: Int?
}

/// A Radarr/Sonarr quality (or language) profile surfaced by Overseerr.
public struct OverseerrProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
}

/// A root-folder option for a server.
public struct OverseerrRootFolder: Codable, Sendable, Equatable {
    public var id: Int?
    public var path: String?
    public var freeSpace: Int64?
}

/// Details for one server (`GET /api/v1/service/{radarr|sonarr}/{id}`): its
/// quality profiles, root folders and (Sonarr) language profiles.
public struct OverseerrServerDetails: Codable, Sendable {
    public var server: OverseerrServer?
    public var profiles: [OverseerrProfile]?
    public var rootFolders: [OverseerrRootFolder]?
    public var languageProfiles: [OverseerrProfile]?
}

/// A title returned by Overseerr's multi-search (`/api/v1/search`).
public struct OverseerrSearchResult: Codable, Sendable, Equatable, Identifiable {
    public var id: Int               // tmdbId
    public var mediaType: String?    // movie | tv | person
    public var title: String?        // movies
    public var name: String?         // tv
    public var posterPath: String?
    public var overview: String?
    public var releaseDate: String?
    public var firstAirDate: String?
    public var mediaInfo: OverseerrMedia?

    public var displayTitle: String { title ?? name ?? "Untitled" }
    public var year: String? { (releaseDate ?? firstAirDate)?.split(separator: "-").first.map(String.init) }
}

public struct OverseerrSearchPage: Codable, Sendable {
    public var page: Int?
    public var totalResults: Int?
    public var results: [OverseerrSearchResult]
}
