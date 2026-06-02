import XCTest
@testable import RadarrKit
import NautilarrCore

final class RadarrClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> RadarrClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://radarr.test:7878")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "k"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return RadarrClient(api: api)
    }

    func testMoviesDecode() async throws {
        let client = makeClient { _ in (200, Fixtures.data("movies")) }
        let movies = try await client.movies()
        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].title, "Example Movie")
        XCTAssertEqual(movies[0].imageURL(), "https://artworks.example/movie-poster.jpg")
        XCTAssertEqual(movies[0].minimumAvailability, "released")
        XCTAssertEqual(movies[1].isAvailable, false)
    }

    func testQueueProgress() async throws {
        let client = makeClient { _ in (200, Fixtures.data("queue")) }
        let queue = try await client.queue()
        let item = try XCTUnwrap(queue.records.first)
        XCTAssertEqual(item.protocolName, "torrent")
        // (8e9 - 2e9)/8e9 = 0.75
        XCTAssertEqual(item.progress, 0.75, accuracy: 0.001)
    }

    func testAddMoviePayload() async throws {
        var body: Data?
        let client = makeClient { request in
            body = request.httpBody ?? request.bodyStreamData()
            return (201, Fixtures.data("movies"))
        }
        let lookup = RadarrMovie(id: 0, title: "New Movie", year: 2025, tmdbId: 42, titleSlug: "new-movie-42")
        let request = RadarrAddMovieRequest(lookup: lookup, qualityProfileId: 3, rootFolderPath: "/movies")
        _ = try? await client.addMovie(request)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "New Movie")
        XCTAssertEqual(json?["qualityProfileId"] as? Int, 3)
        XCTAssertEqual(json?["rootFolderPath"] as? String, "/movies")
        XCTAssertEqual(json?["minimumAvailability"] as? String, "released")
        XCTAssertNotNil(json?["addOptions"])
    }

    func testCommandEncodesMovieSearch() async throws {
        var body: Data?
        let client = makeClient { request in
            body = request.httpBody ?? request.bodyStreamData()
            return (201, #"{"id":3,"name":"MoviesSearch","status":"queued"}"#.data(using: .utf8)!)
        }
        _ = try await client.runCommand(.movieSearch(movieId: 10))
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "MoviesSearch")
        XCTAssertEqual(json?["movieIds"] as? [Int], [10])
    }

    func testUnauthorizedMapsToError() async {
        let client = makeClient { _ in (401, Data()) }
        do { _ = try await client.movies(); XCTFail("expected error") }
        catch let error as APIError { XCTAssertEqual(error, .unauthorized) }
        catch { XCTFail("wrong error") }
    }

    func testEditMoviesEncodesEditorPayload() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.editMovies(ids: [10, 11], monitored: false, qualityProfileId: 7)
        XCTAssertEqual(method, "PUT")
        XCTAssertTrue(path?.hasSuffix("/movie/editor") == true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["movieIds"] as? [Int], [10, 11])
        XCTAssertEqual(json?["monitored"] as? Bool, false)
        XCTAssertEqual(json?["qualityProfileId"] as? Int, 7)
        XCTAssertNil(json?["moveFiles"])
    }

    func testEditMoviesWithRootFolderIncludesMoveFiles() async throws {
        var body: Data?
        let client = makeClient { request in
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.editMovies(ids: [1], rootFolderPath: "/movies2", moveFiles: true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["rootFolderPath"] as? String, "/movies2")
        XCTAssertEqual(json?["moveFiles"] as? Bool, true)
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
