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

    /// A real Jellyfin `/Sessions` element (passed through by Jellystat) carries
    /// many extra PascalCase fields; decoding must survive them and detect play.
    func testSessionsDecodeRealWorldJellyfinShape() async throws {
        let client = makeClient { _ in
            let json = #"""
            [{
              "PlayState":{"PositionTicks":7200000000,"CanSeek":true,"IsPaused":false,
                "IsMuted":false,"MediaSourceId":"a1b2","PlayMethod":"DirectPlay","RepeatMode":"RepeatNone"},
              "RemoteEndPoint":"192.168.1.42","Id":"8f3c","UserId":"2b1a","UserName":"alice",
              "Client":"Jellyfin iOS","ApplicationVersion":"1.3.0","DeviceName":"Alice's iPhone",
              "DeviceId":"ABCD","LastActivityDate":"2026-06-04T18:22:31.0000000Z",
              "NowPlayingItem":{"Name":"Chapter 5","SeriesName":"Some Show","SeriesId":"1111",
                "Id":"9999","Type":"Episode","RunTimeTicks":18000000000,"Container":"mkv",
                "MediaStreams":[{"Type":"Video","Codec":"h264","DisplayTitle":"1080p H264"}],
                "ProviderIds":{"Tvdb":"123456"}}
            }]
            """#
            return (200, json.data(using: .utf8)!)
        }
        let sessions = try await client.sessions()
        XCTAssertEqual(sessions.count, 1)
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.displayTitle, "Some Show — Chapter 5")
        XCTAssertEqual(s.userName, "alice")
        XCTAssertFalse(s.isPaused)
        XCTAssertEqual(s.progress, 0.4, accuracy: 0.001)  // 7.2e9 / 1.8e10
    }

    /// Defensive: if a Jellystat build wraps the array (e.g. `{"sessions":[...]}`)
    /// instead of returning a bare array, we still find the playing session
    /// rather than silently reporting "nothing playing".
    func testSessionsDecodeWrappedEnvelope() async throws {
        let client = makeClient { _ in
            let json = #"{"sessions":[{"Id":"s1","UserName":"bob","NowPlayingItem":{"Name":"Movie","Type":"Movie","RunTimeTicks":72000000000},"PlayState":{"PositionTicks":36000000000,"IsPaused":false}}]}"#
            return (200, json.data(using: .utf8)!)
        }
        let sessions = try await client.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.displayTitle, "Movie")
        XCTAssertEqual(sessions.first?.progress ?? 0, 0.5, accuracy: 0.001)
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

    func testUsersDecode() async throws {
        var path: String?
        let client = makeClient { request in
            path = request.url?.path
            return (200, #"[{"UserId":"abc","UserName":"Alice","TotalPlays":40,"TotalWatchTime":3600,"LastClient":"Web"}]"#.data(using: .utf8)!)
        }
        let users = try await client.users()
        XCTAssertEqual(path, "/stats/getAllUserActivity")
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users[0].userName, "Alice")
        XCTAssertEqual(users[0].totalPlays, 40)
        XCTAssertEqual(users[0].totalWatchTime, 3600)
    }

    func testLibraryCardsDecode() async throws {
        let client = makeClient { _ in
            (200, #"[{"Id":"lib1","Name":"Movies","CollectionType":"movies","Library_Count":500,"Season_Count":0,"Episode_Count":0}]"#.data(using: .utf8)!)
        }
        let libs = try await client.libraryCards()
        XCTAssertEqual(libs.count, 1)
        XCTAssertEqual(libs[0].name, "Movies")
        XCTAssertEqual(libs[0].libraryCount, 500)
        XCTAssertEqual(libs[0].collectionType, "movies")
    }

    func testMostViewedPostsTypeAndDecodes() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod
            path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, #"[{"Id":"i1","Name":"Dune","Plays":12}]"#.data(using: .utf8)!)
        }
        let items = try await client.mostViewed(type: "Movie", days: 30)
        XCTAssertEqual(method, "POST")
        XCTAssertEqual(path, "/stats/getMostViewedByType")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "Movie")
        XCTAssertEqual(json?["days"] as? Int, 30)
        XCTAssertEqual(items.first?.name, "Dune")
        XCTAssertEqual(items.first?.plays, 12)
    }

    func testMostActiveUsersDecodesNameFromUserName() async throws {
        let client = makeClient { _ in
            (200, #"[{"UserId":"u1","Name":"Alice","Plays":40}]"#.data(using: .utf8)!)
        }
        let ranked = try await client.mostActiveUsers(days: 7)
        XCTAssertEqual(ranked.first?.name, "Alice")
        XCTAssertEqual(ranked.first?.entryId, "u1")
        XCTAssertEqual(ranked.first?.plays, 40)
    }
}

private extension URLRequest {
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
