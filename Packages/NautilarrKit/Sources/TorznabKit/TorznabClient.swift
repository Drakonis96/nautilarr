import Foundation
import NautilarrCore

/// Lightweight client for Torznab/Newznab indexer endpoints (NZBHydra2, Jackett).
///
/// By API key these services only expose the Torznab/Newznab feed (XML `t=caps`,
/// `t=search`); their rich management APIs require the admin login, so Nautilarr
/// integrates them at the reachability/caps level (use Prowlarr for full indexer
/// management). The API key is attached as the `apikey` query parameter.
public struct TorznabClient: Sendable {
    private let api: APIClient
    private let capsPath: String

    public init(api: APIClient, capsPath: String) {
        self.api = api
        self.capsPath = capsPath
    }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        // Jackett aggregates all indexers under a torznab path; NZBHydra2 serves
        // the Newznab API at /api.
        self.capsPath = instance.type == .jackett
            ? "api/v2.0/indexers/all/results/torznab/api"
            : "api"
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    public struct Capabilities: Sendable, Equatable {
        public var serverTitle: String?
        public var categoryCount: Int
    }

    /// A single search result from the Torznab/Newznab feed.
    public struct Result: Sendable, Equatable, Hashable, Identifiable {
        public var id: String { guid ?? link ?? title ?? UUID().uuidString }
        public var guid: String?
        public var title: String?
        /// The download URL (`.torrent`, magnet or `.nzb`) or details link.
        public var link: String?
        public var size: Int64?
        public var seeders: Int?
        public var indexer: String?
        public var publishDate: Date?
    }

    /// Free-text search across the indexer(s) (`t=search`). Results are parsed
    /// from the Torznab/Newznab RSS feed. Both `torznab:` and `newznab:`
    /// attribute namespaces are handled.
    public func search(query: String, limit: Int = 100) async throws -> [Result] {
        let items = [
            URLQueryItem(name: "t", value: "search"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        let data = try await api.sendReturningData(.get(capsPath, query: items))
        let xml = String(data: data, encoding: .utf8) ?? ""
        if let description = Self.attribute("description", inElement: "error", of: xml) {
            throw APIError.server(statusCode: 200, body: description)
        }
        if xml.contains("<error") { throw APIError.unauthorized }
        return TorznabFeedParser(data: data).parse()
    }

    /// Fetches `t=caps`. Throws on an `<error>` response (e.g. bad API key) or
    /// an unrecognised body; otherwise returns coarse capability info.
    @discardableResult
    public func capabilities() async throws -> Capabilities {
        let data = try await api.sendReturningData(.get(capsPath, query: [URLQueryItem(name: "t", value: "caps")]))
        let xml = String(data: data, encoding: .utf8) ?? ""

        if let description = Self.attribute("description", inElement: "error", of: xml) {
            throw APIError.server(statusCode: 200, body: description)
        }
        if xml.contains("<error") {
            throw APIError.unauthorized
        }
        guard xml.contains("<caps") || xml.contains("<server") || xml.contains("<categories") else {
            throw APIError.invalidResponse
        }
        let title = Self.attribute("title", inElement: "server", of: xml)
        let categoryCount = xml.components(separatedBy: "<category ").count - 1
        return Capabilities(serverTitle: title, categoryCount: max(0, categoryCount))
    }

    /// Minimal, dependency-free attribute scan (avoids pulling an XML parser for
    /// a single value). Looks for `<element ... attribute="VALUE"`.
    static func attribute(_ attribute: String, inElement element: String, of xml: String) -> String? {
        guard let elementRange = xml.range(of: "<\(element)") else { return nil }
        let tail = xml[elementRange.lowerBound...]
        guard let attrRange = tail.range(of: "\(attribute)=\"") else { return nil }
        let afterAttr = tail[attrRange.upperBound...]
        guard let closingQuote = afterAttr.firstIndex(of: "\"") else { return nil }
        return String(afterAttr[..<closingQuote])
    }
}

// MARK: - RSS feed parser

/// Parses a Torznab/Newznab RSS feed into `TorznabClient.Result`s. Handles the
/// `torznab:`/`newznab:` attribute extensions and the common `<enclosure>` /
/// `<size>` / `<jackettindexer>` variations.
final class TorznabFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    init(data: Data) { self.data = data }

    private var results: [TorznabClient.Result] = []
    private var current: TorznabClient.Result?
    private var text = ""
    private var inItem = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    func parse() -> [TorznabClient.Result] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return results
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.lowercased()
        text = ""
        if name == "item" {
            inItem = true
            current = TorznabClient.Result()
            return
        }
        guard inItem else { return }
        if name == "enclosure" {
            if current?.link == nil { current?.link = attributeDict["url"] }
            if current?.size == nil, let len = attributeDict["length"], let v = Int64(len) { current?.size = v }
        } else if name.hasSuffix("attr") {
            // <torznab:attr name="seeders" value="10"/> (also newznab:)
            guard let attr = attributeDict["name"]?.lowercased(), let value = attributeDict["value"] else { return }
            switch attr {
            case "seeders": current?.seeders = Int(value)
            case "size": if let v = Int64(value) { current?.size = v }
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { text += s }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "item" {
            if let current { results.append(current) }
            current = nil
            inItem = false
            return
        }
        guard inItem else { return }
        switch name {
        case "title": if !value.isEmpty { current?.title = value }
        case "guid": if !value.isEmpty { current?.guid = value }
        case "link": if !value.isEmpty, current?.link == nil { current?.link = value }
        case "size": if let v = Int64(value) { current?.size = v }
        case "jackettindexer", "indexer": if !value.isEmpty { current?.indexer = value }
        case "pubdate": current?.publishDate = Self.dateFormatter.date(from: value)
        default: break
        }
    }
}
