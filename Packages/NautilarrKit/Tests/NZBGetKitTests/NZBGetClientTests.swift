import XCTest
@testable import NZBGetKit
import NautilarrCore

final class NZBGetClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> NZBGetClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://nzbget.test:6789")!] },
            authorizer: BasicAuthorizer(username: "nzbget", password: "pw"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return NZBGetClient(api: api)
    }

    func testGroupsDecodeAndProgress() async throws {
        var auth: String?
        let client = makeClient { request in
            auth = request.value(forHTTPHeaderField: "Authorization")
            return (200, Fixtures.data("listgroups"))
        }
        let groups = try await client.groups()
        XCTAssertTrue(auth?.hasPrefix("Basic ") == true, "Basic auth header must be attached")
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].progress, 0.63, accuracy: 0.001)
        XCTAssertFalse(groups[0].isPaused)
        XCTAssertTrue(groups[1].isPaused)
    }

    func testVersionDecodes() async throws {
        let client = makeClient { _ in (200, #"{"version":"1.1","result":"21.1","id":1}"#.data(using: .utf8)!) }
        let version = try await client.version()
        XCTAssertEqual(version, "21.1")
    }

    func testPauseGroupSendsEditQueue() async throws {
        var body: String?
        let client = makeClient { request in
            body = request.bodyText()
            return (200, #"{"version":"1.1","result":true,"id":1}"#.data(using: .utf8)!)
        }
        let ok = try await client.pauseGroup(id: 7)
        XCTAssertTrue(ok)
        XCTAssertTrue(body?.contains("\"editqueue\"") == true)
        XCTAssertTrue(body?.contains("GroupPause") == true)
        XCTAssertTrue(body?.contains("7") == true)
    }

    func testDeleteGroupUsesFinalDeleteWhenDeletingFiles() async throws {
        var body: String?
        let client = makeClient { request in
            body = request.bodyText()
            return (200, #"{"version":"1.1","result":true,"id":1}"#.data(using: .utf8)!)
        }
        _ = try await client.deleteGroup(id: 3, deleteFiles: true)
        XCTAssertTrue(body?.contains("GroupFinalDelete") == true)
    }
}
