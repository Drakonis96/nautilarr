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
