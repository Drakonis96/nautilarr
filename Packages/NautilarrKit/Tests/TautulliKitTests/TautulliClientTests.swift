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
}
