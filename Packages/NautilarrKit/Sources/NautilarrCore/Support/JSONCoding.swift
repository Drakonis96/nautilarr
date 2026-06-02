import Foundation

public extension JSONDecoder {
    /// A decoder tuned for the *arr / self-hosted REST APIs, which emit ISO-8601
    /// timestamps inconsistently — sometimes with fractional seconds, sometimes
    /// without, and occasionally a date-only value or the .NET sentinel
    /// `0001-01-01T00:00:00Z`. This strategy tries the common shapes and falls
    /// back to `nil`-friendly behaviour rather than throwing.
    static var nautilarr: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Some fields are numeric epochs rather than ISO strings.
            if let epoch = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: epoch)
            }
            let raw = (try? container.decode(String.self)) ?? ""
            if let date = DateParsing.date(from: raw) {
                return date
            }
            // Crucially, DON'T throw on an unparseable/sentinel value (e.g. the
            // .NET `0001-01-01T00:00:00Z` that *arr emits for "never aired").
            // Throwing would abort decoding the ENTIRE response, emptying the
            // whole library over one odd date. Fall back to a far-past date so
            // such fields just read as "unset".
            return .distantPast
        }
        return decoder
    }
}

public extension JSONEncoder {
    /// Matching encoder using fractional-second ISO-8601 output.
    static var nautilarr: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateParsing.iso8601Fractional.string(from: date))
        }
        return encoder
    }
}

/// Date parsing helpers shared by the coders.
enum DateParsing {
    static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(from raw: String) -> Date? {
        if let d = iso8601Fractional.date(from: raw) { return d }
        if let d = iso8601Plain.date(from: raw) { return d }
        if let d = dateOnly.date(from: raw) { return d }
        return nil
    }
}
