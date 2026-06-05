import XCTest
@testable import StatainerKit
import NautilarrCore

final class StatainerClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> StatainerClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "https://statainer.test")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-API-Key", apiKey: "stnr_KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return StatainerClient(api: api)
    }

    func testSystemDecodes() async throws {
        var apiKey: String?
        var path: String?
        let client = makeClient { request in
            apiKey = request.value(forHTTPHeaderField: "X-API-Key")
            path = request.url?.path
            return (200, Fixtures.data("system"))
        }
        let system = try await client.system()
        XCTAssertEqual(apiKey, "stnr_KEY")
        XCTAssertEqual(path, "/api/v1/system")
        XCTAssertEqual(system.cpuCores, 8)
        XCTAssertEqual(system.containersRunning, 9)
        XCTAssertEqual(system.dockerVersion, "27.0.3")
        XCTAssertEqual(system.hostname, "docker-host")
        XCTAssertEqual(system.memoryTotalBytes, 16_777_216_000)
    }

    func testContainersDecode() async throws {
        let client = makeClient { _ in (200, Fixtures.data("containers")) }
        let containers = try await client.containers()
        XCTAssertEqual(containers.count, 2)
        let web = containers[0]
        XCTAssertEqual(web.displayName, "web")
        XCTAssertEqual(web.image, "nginx:latest")
        XCTAssertTrue(web.isRunning)
        XCTAssertTrue(web.hasUpdate)
        let db = containers[1]
        XCTAssertEqual(db.state, .exited)
        XCTAssertFalse(db.isRunning)
        XCTAssertFalse(db.hasUpdate)
    }

    func testStatsDecode() async throws {
        let client = makeClient { _ in (200, Fixtures.data("stats")) }
        let stats = try await client.stats()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].cpu, 12.5)
        XCTAssertEqual(stats[0].mem, 30.1)
        XCTAssertEqual(stats[0].pidCount, 12)
        XCTAssertEqual(stats[0].memoryUsageBytes, Int64(192.4 * 1_048_576))
    }

    func testDashboardMergesStatsIntoContainers() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/v1/system": return (200, Fixtures.data("system"))
            case "/api/v1/containers": return (200, Fixtures.data("containers"))
            case "/api/v1/stats": return (200, Fixtures.data("stats"))
            default: return (404, Data())
            }
        }
        let dashboard = try await client.dashboard()
        XCTAssertEqual(dashboard.system?.hostname, "docker-host")
        XCTAssertEqual(dashboard.containers.count, 2)
        XCTAssertEqual(dashboard.updatesAvailable, 1)
        // The "web" row gains live metrics from /stats; metadata (image) is kept.
        let web = dashboard.containers.first { $0.id == "9f0e1234abcd" }
        XCTAssertEqual(web?.cpu, 12.5)
        XCTAssertEqual(web?.image, "nginx:latest")
        // The "db" row had no stats entry — it survives without live metrics.
        let db = dashboard.containers.first { $0.id == "1a2b3c4d5e6f" }
        XCTAssertNil(db?.cpu)
        XCTAssertEqual(db?.image, "postgres:16")
    }

    func testDashboardSurvivesStatsFailure() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/v1/containers": return (200, Fixtures.data("containers"))
            case "/api/v1/stats": return (502, Data())
            default: return (200, Fixtures.data("system"))
            }
        }
        let dashboard = try await client.dashboard()
        XCTAssertEqual(dashboard.containers.count, 2)
        XCTAssertNil(dashboard.containers.first?.cpu)
    }

    func testRestartActionPostsAndDecodes() async throws {
        var method: String?
        var path: String?
        let client = makeClient { request in
            method = request.httpMethod
            path = request.url?.path
            return (200, Fixtures.data("restart"))
        }
        let result = try await client.restart("9f0e1234abcd")
        XCTAssertEqual(method, "POST")
        XCTAssertEqual(path, "/api/v1/containers/9f0e1234abcd/restart")
        XCTAssertEqual(result.ok, true)
        XCTAssertEqual(result.action, "restart")
        XCTAssertEqual(result.name, "web")
    }

    func testFailedUpdateThrows() async {
        let client = makeClient { _ in
            (409, #"{"ok":false,"action":"update","message":"Pull failed"}"#.data(using: .utf8)!)
        }
        do {
            _ = try await client.update("9f0e1234abcd")
            XCTFail("expected error")
        } catch { /* 409 surfaces as an error — expected */ }
    }

    /// The live server (v0.9.18) reports `update_available` as a JSON bool/null,
    /// not the docs' integer — decoding must tolerate every shape rather than
    /// throwing and emptying the whole container list.
    func testLenientUpdateAvailableShapes() async throws {
        let json = """
        {"count":3,"containers":[
          {"id":"a","name":"bool-true","status":"running","update_available":true},
          {"id":"b","name":"bool-false","status":"running","update_available":false},
          {"id":"c","name":"null","status":"exited","update_available":null}
        ]}
        """
        let client = makeClient { _ in (200, json.data(using: .utf8)!) }
        let containers = try await client.containers()
        XCTAssertEqual(containers.count, 3)
        XCTAssertTrue(containers[0].hasUpdate)
        XCTAssertFalse(containers[1].hasUpdate)
        XCTAssertFalse(containers[2].hasUpdate)
    }

    func testPingDecodes() async throws {
        let client = makeClient { _ in
            (200, #"{"ok":true,"pong":true,"version":"v0.9.17"}"#.data(using: .utf8)!)
        }
        let ping = try await client.ping()
        XCTAssertEqual(ping.pong, true)
        XCTAssertEqual(ping.version, "v0.9.17")
    }
}
