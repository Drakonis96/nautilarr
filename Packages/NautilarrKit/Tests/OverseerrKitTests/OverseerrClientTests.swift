import XCTest
@testable import OverseerrKit
import NautilarrCore

final class OverseerrClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> OverseerrClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://seerr.test:5055")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return OverseerrClient(api: api)
    }

    func testRequestsDecode() async throws {
        var apiKeySeen: String?
        let client = makeClient { request in
            apiKeySeen = request.value(forHTTPHeaderField: "X-Api-Key")
            return (200, Fixtures.data("requests"))
        }
        let page = try await client.requests()
        XCTAssertEqual(apiKeySeen, "KEY")
        XCTAssertEqual(page.results.count, 2)
        XCTAssertEqual(page.results[0].status, .pending)
        XCTAssertEqual(page.results[0].requestedBy?.name, "Alice")
        XCTAssertEqual(page.results[0].mediaType, "movie")
        XCTAssertEqual(page.results[1].status, .approved)
        XCTAssertEqual(page.results[1].requestedBy?.name, "bob")
        XCTAssertNotNil(page.results[0].createdAt)
    }

    func testApprovePostsToCorrectPath() async throws {
        var path: String?
        var method: String?
        let client = makeClient { request in
            path = request.url?.path
            method = request.httpMethod
            return (200, #"{"id":1,"status":2,"type":"movie"}"#.data(using: .utf8)!)
        }
        _ = try await client.approve(requestId: 1)
        XCTAssertEqual(path, "/api/v1/request/1/approve")
        XCTAssertEqual(method, "POST")
    }

    func testDeclinePostsToCorrectPath() async throws {
        var path: String?
        let client = makeClient { request in
            path = request.url?.path
            return (200, #"{"id":1,"status":3,"type":"movie"}"#.data(using: .utf8)!)
        }
        _ = try await client.decline(requestId: 7)
        XCTAssertEqual(path, "/api/v1/request/7/decline")
    }

    func testSearchFiltersOutPeople() async throws {
        var query: [String: String] = [:]
        let client = makeClient { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.forEach { query[$0.name] = $0.value }
            let body = #"{"page":1,"totalResults":3,"results":[{"id":1,"mediaType":"movie","title":"A"},{"id":2,"mediaType":"tv","name":"B"},{"id":3,"mediaType":"person","name":"C"}]}"#
            return (200, body.data(using: .utf8)!)
        }
        let results = try await client.search(query: "matrix")
        XCTAssertEqual(query["query"], "matrix")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.displayTitle), ["A", "B"])
    }

    func testCreateRequestSendsMediaAndSeasons() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (201, Data())
        }
        try await client.createRequest(mediaType: "tv", mediaId: 1399)
        XCTAssertEqual(method, "POST")
        XCTAssertEqual(path, "/api/v1/request")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["mediaType"] as? String, "tv")
        XCTAssertEqual(json?["mediaId"] as? Int, 1399)
        XCTAssertEqual(json?["seasons"] as? String, "all")
    }

    func testMediaDetailsUsesTitleOrName() async throws {
        let client = makeClient { request in
            if request.url?.path.contains("/tv/") == true {
                return (200, #"{"name":"Example Series","posterPath":"/p.jpg"}"#.data(using: .utf8)!)
            }
            return (200, #"{"title":"Example Movie","posterPath":"/m.jpg"}"#.data(using: .utf8)!)
        }
        let movie = try await client.mediaDetails(mediaType: "movie", tmdbId: 555)
        XCTAssertEqual(movie.displayTitle, "Example Movie")
        let tv = try await client.mediaDetails(mediaType: "tv", tmdbId: 1399)
        XCTAssertEqual(tv.displayTitle, "Example Series")
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
