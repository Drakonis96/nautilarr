import XCTest
@testable import QBittorrentKit
import NautilarrCore

final class QBittorrentClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(
        authorizer: RequestAuthorizer,
        route: @escaping (URLRequest) -> (Int, Data)
    ) -> QBittorrentClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://qbit.test:8080")!] },
            authorizer: authorizer,
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return QBittorrentClient(api: api)
    }

    func testLogsInBeforeFirstRequestThenDecodesTorrents() async throws {
        var loginHit = false
        var sentReferer: String?
        let authorizer = QBittorrentAuthorizer(baseURL: URL(string: "http://qbit.test:8080"), username: "admin", password: "pw")
        let client = makeClient(authorizer: authorizer) { request in
            if request.url?.path.hasSuffix("/auth/login") == true {
                loginHit = true
                return (200, Data("Ok.".utf8))
            }
            sentReferer = request.value(forHTTPHeaderField: "Referer")
            return (200, Fixtures.data("torrents"))
        }
        let torrents = try await client.torrents()
        XCTAssertTrue(loginHit, "Authorizer should log in before the first API call")
        XCTAssertEqual(sentReferer, "http://qbit.test:8080")
        XCTAssertEqual(torrents.count, 2)
        XCTAssertEqual(torrents[0].displayState, "Downloading")
        XCTAssertEqual(torrents[0].progress ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertTrue(torrents[1].isPaused)
        XCTAssertTrue(torrents[1].isComplete)
    }

    func testReLoginOn403ThenSucceeds() async throws {
        var loginCount = 0
        var infoCount = 0
        let authorizer = QBittorrentAuthorizer(baseURL: URL(string: "http://qbit.test:8080"), username: "admin", password: "pw")
        let client = makeClient(authorizer: authorizer) { request in
            if request.url?.path.hasSuffix("/auth/login") == true {
                loginCount += 1
                return (200, Data("Ok.".utf8))
            }
            infoCount += 1
            // Fail the first API attempt with 403, succeed after re-login.
            return infoCount == 1 ? (403, Data()) : (200, Fixtures.data("torrents"))
        }
        let torrents = try await client.torrents()
        XCTAssertEqual(torrents.count, 2)
        XCTAssertEqual(loginCount, 2, "Should log in once up front and once after the 403")
    }

    func testPauseSendsHashes() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            if request.url?.path.hasSuffix("/torrents/pause") == true { body = request.bodyText() }
            return (200, Data())
        }
        try await client.pause(hashes: ["abc123def456"])
        XCTAssertEqual(body, "hashes=abc123def456")
    }

    func testPauseAllUsesAllKeyword() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, Data())
        }
        try await client.pause()
        XCTAssertEqual(body, "hashes=all")
    }

    func testDeleteSendsDeleteFilesFlag() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, Data())
        }
        try await client.delete(hashes: ["h1", "h2"], deleteFiles: true)
        XCTAssertTrue(body?.contains("hashes=h1%7Ch2") == true, "hashes should be pipe-joined and encoded")
        XCTAssertTrue(body?.contains("deleteFiles=true") == true)
    }

    func testRecheckSendsHashes() async throws {
        var path: String?; var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            path = request.url?.path
            body = request.bodyText()
            return (200, Data())
        }
        try await client.recheck(hashes: ["h1", "h2"])
        XCTAssertTrue(path?.hasSuffix("/torrents/recheck") == true)
        XCTAssertTrue(body?.contains("hashes=h1%7Ch2") == true)
    }

    func testVersionReadsPlainText() async throws {
        let client = makeClient(authorizer: NoAuthorizer()) { _ in (200, Data("v4.6.2".utf8)) }
        let version = try await client.version()
        XCTAssertEqual(version.version, "v4.6.2")
    }
}
