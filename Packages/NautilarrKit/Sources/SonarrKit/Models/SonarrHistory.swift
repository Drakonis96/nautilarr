import Foundation

/// A history record (`GET /api/v3/history`). The `data` dictionary varies by
/// event type, so it is decoded as a string map for display.
public struct SonarrHistoryRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var episodeId: Int?
    public var seriesId: Int?
    public var sourceTitle: String?
    /// `grabbed`, `downloadFolderImported`, `downloadFailed`,
    /// `episodeFileDeleted`, `episodeFileRenamed`, …
    public var eventType: String?
    public var date: Date?
    public var quality: SonarrQualityModel?
    public var data: [String: String]?
    public var episode: SonarrEpisode?
    public var series: SonarrSeries?

    private enum CodingKeys: String, CodingKey {
        case id, episodeId, seriesId, sourceTitle, eventType, date, quality, data, episode, series
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        episodeId = try c.decodeIfPresent(Int.self, forKey: .episodeId)
        seriesId = try c.decodeIfPresent(Int.self, forKey: .seriesId)
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        quality = try c.decodeIfPresent(SonarrQualityModel.self, forKey: .quality)
        episode = try c.decodeIfPresent(SonarrEpisode.self, forKey: .episode)
        series = try c.decodeIfPresent(SonarrSeries.self, forKey: .series)
        // `data` values can be strings, numbers or bools — coerce all to String.
        if let raw = try? c.decodeIfPresent([String: AnyCodableValue].self, forKey: .data) {
            data = raw.mapValues { $0.stringValue }
        } else {
            data = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(episodeId, forKey: .episodeId)
        try c.encodeIfPresent(seriesId, forKey: .seriesId)
        try c.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
        try c.encodeIfPresent(eventType, forKey: .eventType)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(quality, forKey: .quality)
        try c.encodeIfPresent(episode, forKey: .episode)
        try c.encodeIfPresent(series, forKey: .series)
        try c.encodeIfPresent(data, forKey: .data)
    }
}

public typealias SonarrHistory = SonarrPaged<SonarrHistoryRecord>

/// A tiny type-erased JSON scalar used to flatten heterogeneous `data` maps.
struct AnyCodableValue: Codable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { stringValue = s }
        else if let i = try? c.decode(Int.self) { stringValue = String(i) }
        else if let d = try? c.decode(Double.self) { stringValue = String(d) }
        else if let b = try? c.decode(Bool.self) { stringValue = String(b) }
        else { stringValue = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stringValue)
    }
}
