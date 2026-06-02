import XCTest
@testable import LidarrKit
import NautilarrCore

final class LidarrClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> LidarrClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://lidarr.test:8686")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "k"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return LidarrClient(api: api)
    }

    func testArtistsDecode() async throws {
        let client = makeClient { _ in (200, Fixtures.data("artists")) }
        let artists = try await client.artists()
        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(artists[0].artistName, "Example Artist")
        XCTAssertEqual(artists[0].statistics?.albumCount, 4)
        XCTAssertEqual(artists[0].imageURL(), "https://artworks.example/artist.jpg")
    }

    func testAlbumsDecodeAndUsesArtistIdQuery() async throws {
        var capturedQuery: String?
        let client = makeClient { request in
            capturedQuery = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "artistId" }?.value
            return (200, Fixtures.data("albums"))
        }
        let albums = try await client.albums(artistId: 5)
        XCTAssertEqual(capturedQuery, "5")
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(albums[0].title, "First Album")
        XCTAssertEqual(albums[1].albumType, "EP")
    }

    func testAddArtistPayload() async throws {
        var body: Data?
        let client = makeClient { request in
            body = request.httpBody ?? request.bodyStreamData()
            return (201, Fixtures.data("artists"))
        }
        let lookup = LidarrArtist(id: 0, artistName: "New Artist", foreignArtistId: "mbid-new")
        let request = LidarrAddArtistRequest(lookup: lookup, qualityProfileId: 1, metadataProfileId: 2, rootFolderPath: "/music")
        _ = try? await client.addArtist(request)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["artistName"] as? String, "New Artist")
        XCTAssertEqual(json?["foreignArtistId"] as? String, "mbid-new")
        XCTAssertEqual(json?["metadataProfileId"] as? Int, 2)
        XCTAssertNotNil(json?["addOptions"])
    }

    func testCommandEncodesAlbumSearch() async throws {
        var body: Data?
        let client = makeClient { request in
            body = request.httpBody ?? request.bodyStreamData()
            return (201, #"{"id":9,"name":"AlbumSearch","status":"queued"}"#.data(using: .utf8)!)
        }
        _ = try await client.runCommand(.albumSearch(albumIds: [100, 101]))
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "AlbumSearch")
        XCTAssertEqual(json?["albumIds"] as? [Int], [100, 101])
    }

    func testEditArtistsEncodesEditorPayload() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.editArtists(ids: [5], monitored: true, qualityProfileId: 2, metadataProfileId: 3)
        XCTAssertEqual(method, "PUT")
        XCTAssertTrue(path?.hasSuffix("/artist/editor") == true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["artistIds"] as? [Int], [5])
        XCTAssertEqual(json?["monitored"] as? Bool, true)
        XCTAssertEqual(json?["qualityProfileId"] as? Int, 2)
        XCTAssertEqual(json?["metadataProfileId"] as? Int, 3)
    }

    func testSetAlbumsMonitoredEncodesPayload() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.setAlbumsMonitored(ids: [100], monitored: false)
        XCTAssertEqual(method, "PUT")
        XCTAssertTrue(path?.hasSuffix("/album/monitor") == true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["albumIds"] as? [Int], [100])
        XCTAssertEqual(json?["monitored"] as? Bool, false)
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
