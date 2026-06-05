import Foundation

/// A service-relative API endpoint. Combined with a base URL by `APIClient`.
public struct Endpoint: Sendable {
    /// Path relative to the base URL, e.g. `api/v3/series`. A leading slash is
    /// optional.
    public var path: String
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var body: Data?
    public var additionalHeaders: [String: String]
    /// Per-request timeout override, in seconds. `nil` uses the client's default.
    /// Set this for endpoints that block server-side for far longer than a normal
    /// request — e.g. *arr interactive release search, which queries every
    /// configured indexer synchronously and routinely takes a minute or more.
    public var timeout: TimeInterval?

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        additionalHeaders: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
        self.additionalHeaders = additionalHeaders
        self.timeout = timeout
    }

    public static func get(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval? = nil) -> Endpoint {
        Endpoint(path: path, method: .get, queryItems: query, timeout: timeout)
    }

    /// Builds an `application/x-www-form-urlencoded` POST (used by APIs like
    /// qBittorrent's WebUI). Values are percent-encoded.
    public static func form(_ path: String, method: HTTPMethod = .post, fields: [String: String], extraHeaders: [String: String] = [:]) -> Endpoint {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        var headers = extraHeaders
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        return Endpoint(path: path, method: method, body: Data(body.utf8), additionalHeaders: headers)
    }

    public static func delete(_ path: String, query: [URLQueryItem] = []) -> Endpoint {
        Endpoint(path: path, method: .delete, queryItems: query)
    }

    /// Builds a POST endpoint from a JSON object (heterogeneous values), used by
    /// the JSON-RPC download clients (NZBGet, Transmission, Deluge) whose params
    /// mix strings, ints and arrays.
    public static func jsonObject(_ path: String, method: HTTPMethod = .post, object: [String: Any]) throws -> Endpoint {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return Endpoint(path: path, method: method, body: data, additionalHeaders: ["Content-Type": "application/json"])
    }

    /// Builds an endpoint with a JSON-encoded body and the appropriate
    /// `Content-Type` header.
    public static func json<Body: Encodable>(
        _ path: String,
        method: HTTPMethod = .post,
        body: Body,
        query: [URLQueryItem] = [],
        encoder: JSONEncoder = .nautilarr
    ) throws -> Endpoint {
        let data = try encoder.encode(body)
        return Endpoint(
            path: path,
            method: method,
            queryItems: query,
            body: data,
            additionalHeaders: ["Content-Type": "application/json"]
        )
    }
}
