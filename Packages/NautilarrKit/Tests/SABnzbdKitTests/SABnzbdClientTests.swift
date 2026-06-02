import XCTest
@testable import SABnzbdKit
import NautilarrCore

final class SABnzbdClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> SABnzbdClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://sab.test:8080")!] },
            authorizer: APIKeyQueryAuthorizer(parameterName: "apikey", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return SABnzbdClient(api: api)
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    func testQueueDecodesAndComputesProgress() async throws {
        var modeSeen: String?
        var apikeySeen: String?
        let client = makeClient { request in
            modeSeen = self.query(request, "mode")
            apikeySeen = self.query(request, "apikey")
            return (200, Fixtures.data("queue"))
        }
        let queue = try await client.queue()
        XCTAssertEqual(modeSeen, "queue")
        XCTAssertEqual(apikeySeen, "KEY", "API key must be attached as a query param")
        XCTAssertEqual(queue.slots.count, 2)
        XCTAssertEqual(queue.slots[0].progress, 0.63, accuracy: 0.001)
        XCTAssertFalse(queue.slots[0].isPaused)
        XCTAssertTrue(queue.slots[1].isPaused)
        XCTAssertEqual(queue.speed, "3.5 M")
    }

    func testOutputJSONAlwaysRequested() async throws {
        var outputSeen: String?
        let client = makeClient { request in
            outputSeen = self.query(request, "output")
            return (200, Fixtures.data("queue"))
        }
        _ = try await client.queue()
        XCTAssertEqual(outputSeen, "json")
    }

    func testPauseAllUsesPauseMode() async throws {
        var modeSeen: String?
        let client = makeClient { request in
            modeSeen = self.query(request, "mode")
            return (200, Data("{\"status\": true}".utf8))
        }
        try await client.pauseAll()
        XCTAssertEqual(modeSeen, "pause")
    }

    func testDeleteSendsDelFilesAndNzoId() async throws {
        var nameSeen: String?
        var valueSeen: String?
        var delFilesSeen: String?
        let client = makeClient { request in
            nameSeen = self.query(request, "name")
            valueSeen = self.query(request, "value")
            delFilesSeen = self.query(request, "del_files")
            return (200, Data("{\"status\": true}".utf8))
        }
        try await client.delete(nzoId: "SABnzbd_nzo_abc", deleteFiles: true)
        XCTAssertEqual(nameSeen, "delete")
        XCTAssertEqual(valueSeen, "SABnzbd_nzo_abc")
        XCTAssertEqual(delFilesSeen, "1")
    }
}
