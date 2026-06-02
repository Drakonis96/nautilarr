import XCTest
@testable import NautilarrCore

private struct Probe: Codable, Equatable { let value: String }

final class APIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.setHandler(nil)
        super.tearDown()
    }

    private func makeClient(
        urls: [URL] = [URL(string: "http://host.test:8989")!],
        authorizer: RequestAuthorizer = NoAuthorizer(),
        headers: [String: String] = [:]
    ) -> APIClient {
        APIClient(
            baseURLProvider: { urls },
            authorizer: authorizer,
            extraHeaders: headers,
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
    }

    func testDecodesSuccessfulResponse() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/api/v3/probe")
            let body = #"{"value":"ok"}"#.data(using: .utf8)!
            return (.make(url: request.url!, status: 200), body)
        }
        let client = makeClient()
        let probe: Probe = try await client.send(.get("api/v3/probe"))
        XCTAssertEqual(probe, Probe(value: "ok"))
    }

    func testAppendsAPIKeyHeader() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "secret")
            return (.make(url: request.url!, status: 200), #"{"value":"ok"}"#.data(using: .utf8)!)
        }
        let client = makeClient(authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "secret"))
        _ = try await client.send(.get("api/v3/probe")) as Probe
    }

    func testAppendsCustomHeaders() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "abc")
            return (.make(url: request.url!, status: 200), #"{"value":"ok"}"#.data(using: .utf8)!)
        }
        let client = makeClient(headers: ["CF-Access-Client-Id": "abc"])
        _ = try await client.send(.get("api/v3/probe")) as Probe
    }

    func testAPIKeyQueryAuthorizerAppendsParameter() async throws {
        MockURLProtocol.setHandler { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let apikey = comps?.queryItems?.first { $0.name == "apikey" }?.value
            XCTAssertEqual(apikey, "k")
            return (.make(url: request.url!, status: 200), #"{"value":"ok"}"#.data(using: .utf8)!)
        }
        let client = makeClient(authorizer: APIKeyQueryAuthorizer(parameterName: "apikey", apiKey: "k"))
        _ = try await client.send(.get("api/v2", query: [URLQueryItem(name: "mode", value: "queue")])) as Probe
    }

    func testUnauthorizedMapsToError() async throws {
        MockURLProtocol.setHandler { request in
            (.make(url: request.url!, status: 401), Data())
        }
        let client = makeClient()
        do {
            _ = try await client.send(.get("api/v3/probe")) as Probe
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testServerErrorCarriesStatusAndBody() async throws {
        MockURLProtocol.setHandler { request in
            (.make(url: request.url!, status: 500), "boom".data(using: .utf8)!)
        }
        let client = makeClient()
        do {
            _ = try await client.send(.get("api/v3/probe")) as Probe
            XCTFail("Expected server error")
        } catch let APIError.server(status, body) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(body, "boom")
        }
    }

    func testFailoverToSecondHostOnTransportError() async throws {
        let primary = URL(string: "http://lan.test:8989")!
        let fallback = URL(string: "http://wan.test:8989")!
        MockURLProtocol.setHandler { request in
            if request.url?.host == "lan.test" {
                throw URLError(.cannotConnectToHost)
            }
            return (.make(url: request.url!, status: 200), #"{"value":"wan"}"#.data(using: .utf8)!)
        }
        let client = makeClient(urls: [primary, fallback])
        let probe: Probe = try await client.send(.get("api/v3/probe"))
        XCTAssertEqual(probe.value, "wan")
    }

    func testFailsOverToFallbackOnPrimaryHTTPError() async throws {
        // Off-LAN, the primary host address may be answered by some other device
        // with a non-success HTTP response (e.g. 404 / HTML). The client must
        // still fall over to the WAN/reverse-proxy fallback and succeed there.
        let primary = URL(string: "http://lan.test:8989")!
        let fallback = URL(string: "https://wan.example.com")!
        MockURLProtocol.setHandler { request in
            if request.url?.host == "lan.test" {
                return (.make(url: request.url!, status: 404), Data("<html>router</html>".utf8))
            }
            return (.make(url: request.url!, status: 200), #"{"value":"wan"}"#.data(using: .utf8)!)
        }
        let client = makeClient(urls: [primary, fallback])
        let probe: Probe = try await client.send(.get("api/v3/probe"))
        XCTAssertEqual(probe.value, "wan", "Should recover via the fallback host")
    }

    func testReportsAuthErrorWhenAllHostsReturn401() async throws {
        // When every host answers 401, surface the actionable auth error rather
        // than a generic "all hosts failed".
        let primary = URL(string: "http://lan.test:8989")!
        let fallback = URL(string: "https://wan.example.com")!
        MockURLProtocol.setHandler { request in (.make(url: request.url!, status: 401), Data()) }
        let client = makeClient(urls: [primary, fallback])
        do {
            _ = try await client.send(.get("api/v3/probe")) as Probe
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testAllHostsFailed() async throws {
        let primary = URL(string: "http://lan.test:8989")!
        let fallback = URL(string: "http://wan.test:8989")!
        MockURLProtocol.setHandler { _ in throw URLError(.cannotConnectToHost) }
        let client = makeClient(urls: [primary, fallback])
        do {
            _ = try await client.send(.get("api/v3/probe")) as Probe
            XCTFail("Expected failure")
        } catch let APIError.allHostsFailed(reasons) {
            XCTAssertEqual(reasons.count, 2)
        }
    }
}
