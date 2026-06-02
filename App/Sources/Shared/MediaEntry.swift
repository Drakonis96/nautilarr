import Foundation
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit

/// A Sonarr series paired with its instance, used by the series detail screen.
struct LibraryItem: Identifiable, Hashable {
    let instance: ServiceInstance
    let series: SonarrSeries
    var id: String { "\(instance.id)-\(series.id)" }
}

/// The kind of media a library entry represents, used for filtering/segmenting.
enum MediaKind: String, CaseIterable, Identifiable, Hashable {
    case series, movie, artist
    var id: String { rawValue }
    var plural: String {
        switch self {
        case .series: return "Series"
        case .movie: return "Movies"
        case .artist: return "Artists"
        }
    }
    var singular: String {
        switch self {
        case .series: return "Series"
        case .movie: return "Movie"
        case .artist: return "Artist"
        }
    }
    var symbol: String {
        switch self {
        case .series: return "tv"
        case .movie: return "film"
        case .artist: return "music.mic"
        }
    }
}

/// A unified library entry across the *arr media-management services, so a
/// single grid can present TV series, movies and music artists together.
enum MediaEntry: Identifiable, Hashable, Sendable {
    case series(instance: ServiceInstance, series: SonarrSeries)
    case movie(instance: ServiceInstance, movie: RadarrMovie)
    case artist(instance: ServiceInstance, artist: LidarrArtist)

    var instance: ServiceInstance {
        switch self {
        case let .series(instance, _): return instance
        case let .movie(instance, _): return instance
        case let .artist(instance, _): return instance
        }
    }

    var kind: MediaKind {
        switch self {
        case .series: return .series
        case .movie: return .movie
        case .artist: return .artist
        }
    }

    var id: String {
        switch self {
        case let .series(instance, series): return "series-\(instance.id)-\(series.id)"
        case let .movie(instance, movie): return "movie-\(instance.id)-\(movie.id)"
        case let .artist(instance, artist): return "artist-\(instance.id)-\(artist.id)"
        }
    }

    var title: String {
        switch self {
        case let .series(_, series): return series.title
        case let .movie(_, movie): return movie.title
        case let .artist(_, artist): return artist.artistName
        }
    }

    var sortKey: String {
        switch self {
        case let .series(_, series): return (series.sortTitle ?? series.title).lowercased()
        case let .movie(_, movie): return (movie.sortTitle ?? movie.title).lowercased()
        case let .artist(_, artist): return artist.artistName.lowercased()
        }
    }

    var posterURLString: String? {
        switch self {
        case let .series(_, series): return series.imageURL(coverType: "poster")
        case let .movie(_, movie): return movie.imageURL(coverType: "poster")
        case let .artist(_, artist): return artist.imageURL(coverType: "poster")
        }
    }

    var isMonitored: Bool {
        switch self {
        case let .series(_, series): return series.monitored ?? false
        case let .movie(_, movie): return movie.monitored ?? false
        case let .artist(_, artist): return artist.monitored ?? false
        }
    }

    // MARK: - Management accessors

    /// The numeric service-side id of this item (seriesId / movieId / artistId).
    var mediaId: Int {
        switch self {
        case let .series(_, series): return series.id
        case let .movie(_, movie): return movie.id
        case let .artist(_, artist): return artist.id
        }
    }

    var qualityProfileId: Int? {
        switch self {
        case let .series(_, series): return series.qualityProfileId
        case let .movie(_, movie): return movie.qualityProfileId
        case let .artist(_, artist): return artist.qualityProfileId
        }
    }

    /// Lidarr-only metadata profile id (nil for series/movies).
    var metadataProfileId: Int? {
        switch self {
        case let .artist(_, artist): return artist.metadataProfileId
        default: return nil
        }
    }

    /// Filesystem path of the item (e.g. `/tv/Show Name`); its parent is the
    /// root folder. Used to pre-select the current root folder when editing.
    var path: String? {
        switch self {
        case let .series(_, series): return series.path
        case let .movie(_, movie): return movie.path
        case let .artist(_, artist): return artist.path
        }
    }

    /// On-disk size, used for sorting/grouping the library.
    var sizeOnDisk: Int64? {
        switch self {
        case let .series(_, series): return series.statistics?.sizeOnDisk
        case let .movie(_, movie): return movie.sizeOnDisk
        case let .artist(_, artist): return artist.statistics?.sizeOnDisk
        }
    }

    /// Date the item was added to its service, used for sorting.
    var added: Date? {
        switch self {
        case let .series(_, series): return series.added
        case let .movie(_, movie): return movie.added
        case let .artist(_, artist): return artist.added
        }
    }

    // MARK: - Rich list-card details

    var year: Int? {
        switch self {
        case let .series(_, series): return series.year
        case let .movie(_, movie): return movie.year
        case .artist: return nil
        }
    }

    /// Provider/year line, e.g. "Paramount+ · 2021".
    var subtitle: String {
        switch self {
        case let .series(_, series):
            return [series.network, series.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        case let .movie(_, movie):
            return [movie.studio, movie.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        case let .artist(_, artist):
            return artist.genres?.prefix(2).joined(separator: ", ") ?? ""
        }
    }

    /// Library-completion line, e.g. "2 Seasons · 15/15".
    var detail: String {
        switch self {
        case let .series(_, series):
            let seasons = series.statistics?.seasonCount ?? series.seasons?.count ?? 0
            let have = series.statistics?.episodeFileCount ?? 0
            let total = series.statistics?.totalEpisodeCount ?? 0
            return "\(seasons) Season\(seasons == 1 ? "" : "s") · \(have)/\(total)"
        case let .movie(_, movie):
            return movie.hasFile == true ? "Downloaded" : (movie.isAvailable == true ? "Missing" : "Not yet released")
        case let .artist(_, artist):
            let albums = artist.statistics?.albumCount ?? 0
            let have = artist.statistics?.trackFileCount ?? 0
            let total = artist.statistics?.trackCount ?? 0
            return "\(albums) Albums · \(have)/\(total) tracks"
        }
    }

    var overview: String? {
        switch self {
        case let .series(_, series): return series.overview
        case let .movie(_, movie): return movie.overview
        case let .artist(_, artist): return artist.overview
        }
    }

    var genres: [String] {
        switch self {
        case let .series(_, series): return series.genres ?? []
        case let .movie(_, movie): return movie.genres ?? []
        case let .artist(_, artist): return artist.genres ?? []
        }
    }

    /// Whether the library item is fully downloaded.
    var isComplete: Bool {
        switch self {
        case let .series(_, series):
            let have = series.statistics?.episodeFileCount ?? 0
            let total = series.statistics?.totalEpisodeCount ?? 0
            return total > 0 && have >= total
        case let .movie(_, movie): return movie.hasFile == true
        case let .artist(_, artist):
            let have = artist.statistics?.trackFileCount ?? 0
            let total = artist.statistics?.trackCount ?? 0
            return total > 0 && have >= total
        }
    }

    /// Short status word (Continuing/Ended/Released/Announced…).
    var statusText: String? {
        switch self {
        case let .series(_, series): return series.status?.capitalized
        case let .movie(_, movie): return movie.status?.capitalized
        case let .artist(_, artist): return artist.status?.capitalized
        }
    }
}
