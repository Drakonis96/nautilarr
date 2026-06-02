import XCTest
@testable import UnraidKit
import NautilarrCore

final class UnraidClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> UnraidClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "https://unraid.test")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "x-api-key", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return UnraidClient(api: api)
    }

    func testSnapshotDecodes() async throws {
        var apiKey: String?
        var path: String?
        let client = makeClient { request in
            apiKey = request.value(forHTTPHeaderField: "x-api-key")
            path = request.url?.path
            return (200, Fixtures.data("snapshot"))
        }
        let snapshot = try await client.snapshot()
        XCTAssertEqual(apiKey, "KEY")
        XCTAssertEqual(path, "/graphql")
        XCTAssertEqual(snapshot.info?.cpu?.brand, "Ryzen 7 5700G")
        XCTAssertEqual(snapshot.array?.state, "STARTED")
        XCTAssertEqual(snapshot.totalContainers, 2)
        XCTAssertEqual(snapshot.runningContainers, 1)
        XCTAssertEqual(snapshot.dockerContainers?.first?.displayName, "sonarr")
        XCTAssertTrue(snapshot.dockerContainers?.first?.isRunning == true)
    }

    func testGraphQLErrorsAreSurfaced() async {
        let client = makeClient { _ in
            (200, #"{"data":null,"errors":[{"message":"Unauthorized"}]}"#.data(using: .utf8)!)
        }
        do { _ = try await client.snapshot(); XCTFail("expected error") }
        catch let APIError.server(_, body) { XCTAssertEqual(body, "Unauthorized") }
        catch { XCTFail("wrong error: \(error)") }
    }

    func testSendsQueryInBody() async throws {
        var body: String?
        let client = makeClient { request in
            if let data = request.httpBody { body = String(data: data, encoding: .utf8) }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var d = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buf.deallocate() }
                while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 4096); if n <= 0 { break }; d.append(buf, count: n) }
                body = String(data: d, encoding: .utf8)
            }
            return (200, Fixtures.data("snapshot"))
        }
        _ = try await client.snapshot()
        XCTAssertTrue(body?.contains("dockerContainers") == true)
        XCTAssertTrue(body?.contains("\"query\"") == true)
    }
}
