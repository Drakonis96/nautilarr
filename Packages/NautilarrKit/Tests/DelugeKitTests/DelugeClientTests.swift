import XCTest
@testable import DelugeKit
import NautilarrCore

final class DelugeClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(
        authorizer: RequestAuthorizer,
        route: @escaping (URLRequest) -> (Int, Data)
    ) -> DelugeClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://deluge.test:8112")!] },
            authorizer: authorizer,
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return DelugeClient(api: api)
    }

    func testLogsInThenDecodesTorrents() async throws {
        var loginHit = false
        let authorizer = DelugeAuthorizer(baseURL: URL(string: "http://deluge.test:8112"), password: "deluge")
        let client = makeClient(authorizer: authorizer) { request in
            let body = request.bodyText()
            if body.contains("auth.login") {
                loginHit = true
                return (200, #"{"result":true,"error":null,"id":1}"#.data(using: .utf8)!)
            }
            return (200, Fixtures.data("torrents"))
        }
        let torrents = try await client.torrents()
        XCTAssertTrue(loginHit, "Authorizer should log in before the first RPC call")
        XCTAssertEqual(torrents.count, 1)
        XCTAssertEqual(torrents[0].id, "abc123hash", "Hash key should be injected as the id")
        XCTAssertEqual(torrents[0].fractionDone, 0.425, accuracy: 0.0001)
        XCTAssertEqual(torrents[0].state, "Downloading")
    }

    func testBadLoginThrows() async {
        let authorizer = DelugeAuthorizer(baseURL: URL(string: "http://deluge.test:8112"), password: "wrong")
        let client = makeClient(authorizer: authorizer) { _ in
            (200, #"{"result":false,"error":null,"id":1}"#.data(using: .utf8)!)
        }
        do { _ = try await client.torrents(); XCTFail("expected unauthorized") }
        catch let error as APIError { XCTAssertEqual(error, .unauthorized) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testRemoveSendsParams() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, #"{"result":true,"error":null,"id":1}"#.data(using: .utf8)!)
        }
        try await client.remove(hash: "abc123hash", removeData: true)
        XCTAssertTrue(body?.contains("core.remove_torrent") == true)
        XCTAssertTrue(body?.contains("abc123hash") == true)
    }

    func testAddMagnetSendsMethodAndURI() async throws {
        var body: String?
        let client = makeClient(authorizer: NoAuthorizer()) { request in
            body = request.bodyText()
            return (200, #"{"result":null,"error":null,"id":1}"#.data(using: .utf8)!)
        }
        try await client.addMagnet("magnet:?xt=urn:btih:abc")
        XCTAssertTrue(body?.contains("core.add_torrent_magnet") == true)
        XCTAssertTrue(body?.contains("magnet:?xt=urn:btih:abc") == true)
    }

    func testRPCErrorIsSurfaced() async {
        let client = makeClient(authorizer: NoAuthorizer()) { _ in
            (200, #"{"result":null,"error":{"message":"No such method","code":-32601},"id":1}"#.data(using: .utf8)!)
        }
        do { _ = try await client.torrents(); XCTFail("expected error") }
        catch let APIError.server(_, body) { XCTAssertEqual(body, "No such method") }
        catch { XCTFail("wrong error: \(error)") }
    }
}
