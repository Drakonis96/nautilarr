import XCTest
@testable import ProwlarrKit
import NautilarrCore

final class ProwlarrClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> ProwlarrClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://prowlarr.test:9696")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return ProwlarrClient(api: api)
    }

    func testIndexersDecode() async throws {
        var apiKey: String?
        var path: String?
        let client = makeClient { request in
            apiKey = request.value(forHTTPHeaderField: "X-Api-Key")
            path = request.url?.path
            return (200, Fixtures.data("indexers"))
        }
        let indexers = try await client.indexers()
        XCTAssertEqual(apiKey, "KEY")
        XCTAssertEqual(path, "/api/v1/indexer")
        XCTAssertEqual(indexers.count, 2)
        XCTAssertEqual(indexers[0].protocolName, "torrent")
        XCTAssertEqual(indexers[0].enable, true)
        XCTAssertEqual(indexers[1].enable, false)
    }

    func testSystemStatusDecodes() async throws {
        let client = makeClient { _ in (200, #"{"version":"1.21.2","appName":"Prowlarr"}"#.data(using: .utf8)!) }
        let status = try await client.systemStatus()
        XCTAssertEqual(status.version, "1.21.2")
    }

    func testSearchBuildsQueryAndDecodes() async throws {
        var path: String?
        var query: [String: String] = [:]
        let client = makeClient { request in
            path = request.url?.path
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.forEach { query[$0.name] = $0.value }
            let body = #"[{"guid":"abc","title":"Example Release","indexer":"Demo","indexerId":3,"seeders":42,"size":123456,"protocol":"torrent"}]"#
            return (200, body.data(using: .utf8)!)
        }
        let results = try await client.search(query: "the matrix", indexerIds: [3, 5])
        XCTAssertEqual(path, "/api/v1/search")
        XCTAssertEqual(query["query"], "the matrix")
        XCTAssertEqual(query["type"], "search")
        XCTAssertEqual(query["indexerIds"], "3,5")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].seeders, 42)
        XCTAssertEqual(results[0].protocolName, "torrent")
    }

    func testSetIndexerEnabledRoundTripsPreservingFields() async throws {
        var putMethod: String?; var putPath: String?; var putBody: Data?
        let client = makeClient { request in
            if request.httpMethod == "GET" {
                let body = #"{"id":3,"name":"Demo","enable":true,"protocol":"torrent","fields":[{"name":"baseUrl","value":"http://x"}]}"#
                return (200, body.data(using: .utf8)!)
            }
            putMethod = request.httpMethod
            putPath = request.url?.path
            putBody = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.setIndexerEnabled(id: 3, enabled: false)
        XCTAssertEqual(putMethod, "PUT")
        XCTAssertEqual(putPath, "/api/v1/indexer/3")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(putBody)) as? [String: Any]
        XCTAssertEqual(json?["enable"] as? Bool, false)
        XCTAssertEqual(json?["id"] as? Int, 3)
        XCTAssertNotNil(json?["fields"]) // unmapped fields survive the round-trip
    }

    func testGrabPostsGuidAndIndexerId() async throws {
        var method: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        var result = ProwlarrSearchResult()
        result.guid = "abc"; result.indexerId = 7
        try await client.grab(result)
        XCTAssertEqual(method, "POST")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["guid"] as? String, "abc")
        XCTAssertEqual(json?["indexerId"] as? Int, 7)
    }
}

private extension URLRequest {
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data(); let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
