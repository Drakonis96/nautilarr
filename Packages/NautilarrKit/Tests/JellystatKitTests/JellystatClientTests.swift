import XCTest
@testable import JellystatKit
import NautilarrCore

final class JellystatClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> JellystatClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://jellystat.test:3000")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "x-api-token", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return JellystatClient(api: api)
    }

    func testSessionsDecodeAndFilterIdle() async throws {
        var apiKey: String?
        var path: String?
        let client = makeClient { request in
            apiKey = request.value(forHTTPHeaderField: "x-api-token")
            path = request.url?.path
            return (200, Fixtures.data("sessions"))
        }
        let sessions = try await client.sessions()
        XCTAssertEqual(apiKey, "KEY")
        XCTAssertEqual(path, "/proxy/getSessions")
        // The idle session (no NowPlayingItem) is filtered out.
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].displayTitle, "Example Show — Pilot")
        XCTAssertEqual(sessions[0].progress, 0.5, accuracy: 0.001)
        XCTAssertFalse(sessions[0].isPaused)
        XCTAssertTrue(sessions[1].isPaused)
        XCTAssertEqual(sessions[1].displayTitle, "Example Movie")
    }

    func testReachableHitsGetLibraries() async throws {
        var path: String?
        let client = makeClient { request in
            path = request.url?.path
            return (200, "[]".data(using: .utf8)!)
        }
        try await client.testReachable()
        XCTAssertEqual(path, "/api/getLibraries")
    }
}
