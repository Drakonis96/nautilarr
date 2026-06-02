import XCTest
@testable import TransmissionKit
import NautilarrCore

final class TransmissionClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(
        authorizer: RequestAuthorizer,
        route: @escaping (URLRequest) -> (Int, [String: String], Data)
    ) -> TransmissionClient {
        MockURLProtocol.setHandler { request in
            let (status, headers, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://transmission.test:9091")!] },
            authorizer: authorizer,
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return TransmissionClient(api: api)
    }

    func testSessionIdChallengeFlow() async throws {
        var attempts = 0
        var retryCarriedSessionId: String?
        let authorizer = TransmissionAuthorizer(username: nil, password: nil)
        let client = makeClient(authorizer: authorizer) { request in
            attempts += 1
            let sid = request.value(forHTTPHeaderField: "X-Transmission-Session-Id")
            if sid == nil {
                // First attempt: challenge with the session id in the response header.
                return (409, ["X-Transmission-Session-Id": "session-xyz"], Data("requires session id".utf8))
            }
            retryCarriedSessionId = sid
            return (200, [:], Fixtures.data("torrents"))
        }
        let torrents = try await client.torrents()
        XCTAssertEqual(attempts, 2, "Should challenge once then retry")
        XCTAssertEqual(retryCarriedSessionId, "session-xyz")
        XCTAssertEqual(torrents.count, 2)
        XCTAssertEqual(torrents[0].displayState, "Downloading")
        XCTAssertEqual(torrents[0].progress, 0.55, accuracy: 0.001)
        XCTAssertTrue(torrents[1].isPaused)
    }

    func testStopSendsIds() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, [:], #"{"result":"success","arguments":{}}"#.data(using: .utf8)!)
        }
        try await client.stop(ids: [1, 2])
        XCTAssertTrue(body?.contains("torrent-stop") == true)
        XCTAssertTrue(body?.contains("\"ids\"") == true)
    }

    func testRemoveSendsDeleteFlag() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, [:], #"{"result":"success","arguments":{}}"#.data(using: .utf8)!)
        }
        try await client.remove(ids: [5], deleteData: true)
        XCTAssertTrue(body?.contains("torrent-remove") == true)
        XCTAssertTrue(body?.contains("delete-local-data") == true)
    }

    func testAddMagnetSendsFilename() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, [:], #"{"result":"success","arguments":{}}"#.data(using: .utf8)!)
        }
        try await client.addMagnet("magnet:?xt=urn:btih:abc")
        XCTAssertTrue(body?.contains("torrent-add") == true)
        XCTAssertTrue(body?.contains("filename") == true)
        XCTAssertTrue(body?.contains("magnet:?xt=urn:btih:abc") == true)
    }

    func testVersionReadsSessionGet() async throws {
        let client = makeClient(authorizer: NoAuthorizer()) { _ in
            (200, [:], #"{"result":"success","arguments":{"version":"4.0.5"}}"#.data(using: .utf8)!)
        }
        let version = try await client.version()
        XCTAssertEqual(version, "4.0.5")
    }
}
