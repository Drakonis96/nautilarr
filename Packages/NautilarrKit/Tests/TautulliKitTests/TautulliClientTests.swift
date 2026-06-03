import XCTest
@testable import TautulliKit
import NautilarrCore

final class TautulliClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> TautulliClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://tautulli.test:8181")!] },
            authorizer: APIKeyQueryAuthorizer(parameterName: "apikey", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return TautulliClient(api: api)
    }

    func testActivityDecodesSessions() async throws {
        var cmd: String?
        var apikey: String?
        let client = makeClient { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            cmd = comps?.queryItems?.first { $0.name == "cmd" }?.value
            apikey = comps?.queryItems?.first { $0.name == "apikey" }?.value
            return (200, Fixtures.data("activity"))
        }
        let activity = try await client.activity()
        XCTAssertEqual(cmd, "get_activity")
        XCTAssertEqual(apikey, "KEY")
        XCTAssertEqual(activity.count, 2)
        XCTAssertEqual(activity.sessions.first?.displayTitle, "Example Show - S01E01")
        XCTAssertEqual(activity.sessions.first?.progress ?? 0, 0.37, accuracy: 0.001)
        XCTAssertTrue(activity.sessions.first?.isTranscoding == true)
        XCTAssertEqual(activity.sessions.first?.user, "alice")
    }

    func testErrorResultIsSurfaced() async {
        let client = makeClient { _ in
            (200, #"{"response":{"result":"error","message":"Invalid apikey","data":null}}"#.data(using: .utf8)!)
        }
        do { _ = try await client.activity(); XCTFail("expected error") }
        catch let APIError.server(_, body) { XCTAssertEqual(body, "Invalid apikey") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testHistoryDecodes() async throws {
        var cmd: String?
        let client = makeClient { request in
            cmd = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "cmd" }?.value
            let json = #"{"response":{"result":"success","data":{"recordsTotal":2,"data":[{"row_id":5,"date":1700000000,"friendly_name":"Alice","full_title":"Show - S01E01","user":"alice","player":"Chrome","media_type":"episode","transcode_decision":"transcode","percent_complete":80}]}}}"#
            return (200, json.data(using: .utf8)!)
        }
        let history = try await client.history()
        XCTAssertEqual(cmd, "get_history")
        XCTAssertEqual(history.recordsTotal, 2)
        XCTAssertEqual(history.data.count, 1)
        XCTAssertEqual(history.data[0].displayTitle, "Show - S01E01")
        XCTAssertEqual(history.data[0].percentComplete, 80)
        XCTAssertTrue(history.data[0].isTranscoding)
        XCTAssertNotNil(history.data[0].date)
    }

    func testHomeStatsDecode() async throws {
        let client = makeClient { _ in
            let json = #"{"response":{"result":"success","data":[{"stat_id":"top_movies","stat_title":"Most Watched Movies","rows":[{"title":"Dune","total_plays":12,"rating_key":"1"}]},{"stat_id":"top_users","stat_title":"Most Active Users","rows":[{"friendly_name":"Alice","total_plays":40}]}]}}"#
            return (200, json.data(using: .utf8)!)
        }
        let stats = try await client.homeStats()
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].statId, "top_movies")
        XCTAssertEqual(stats[0].rows.first?.label, "Dune")
        XCTAssertEqual(stats[0].rows.first?.totalPlays, 12)
        XCTAssertEqual(stats[1].rows.first?.label, "Alice")
    }

    func testUsersAndLibrariesTablesDecode() async throws {
        let users = try await makeClient { _ in
            (200, #"{"response":{"result":"success","data":{"data":[{"user_id":1,"friendly_name":"Alice","plays":40,"duration":3600,"last_seen":1700000000,"platform":"Chrome"}]}}}"#.data(using: .utf8)!)
        }.usersTable()
        XCTAssertEqual(users.data.count, 1)
        XCTAssertEqual(users.data[0].friendlyName, "Alice")
        XCTAssertEqual(users.data[0].plays, 40)
        XCTAssertNotNil(users.data[0].lastSeenDate)

        let libs = try await makeClient { _ in
            (200, #"{"response":{"result":"success","data":{"data":[{"section_id":1,"section_name":"Movies","section_type":"movie","count":500,"plays":1200}]}}}"#.data(using: .utf8)!)
        }.librariesTable()
        XCTAssertEqual(libs.data.count, 1)
        XCTAssertEqual(libs.data[0].sectionName, "Movies")
        XCTAssertEqual(libs.data[0].count, 500)
    }

    func testTerminateSessionSendsKey() async throws {
        var cmd: String?; var key: String?
        let client = makeClient { request in
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            cmd = q?.first { $0.name == "cmd" }?.value
            key = q?.first { $0.name == "session_key" }?.value
            return (200, #"{"response":{"result":"success","message":null}}"#.data(using: .utf8)!)
        }
        try await client.terminateSession(sessionKey: "abc123", message: "Stopped by admin")
        XCTAssertEqual(cmd, "terminate_session")
        XCTAssertEqual(key, "abc123")
    }
}
