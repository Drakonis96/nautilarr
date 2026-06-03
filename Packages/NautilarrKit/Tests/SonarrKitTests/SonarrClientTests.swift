import XCTest
@testable import SonarrKit
import NautilarrCore

final class SonarrClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.setHandler(nil)
        super.tearDown()
    }

    /// Builds a Sonarr client whose requests are served from fixtures, routed by
    /// path suffix. Also captures the most recent request for assertions.
    private func makeClient(
        route: @escaping (URLRequest) -> (Int, Data)
    ) -> SonarrClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://sonarr.test:8989")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "testkey"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return SonarrClient(api: api)
    }

    func testSystemStatusDecodes() async throws {
        let client = makeClient { _ in (200, Fixtures.data("system_status")) }
        let status = try await client.systemStatus()
        XCTAssertEqual(status.version, "4.0.9.2244")
        XCTAssertEqual(status.appName, "Sonarr")
    }

    func testHealthDecodesSeverity() async throws {
        let client = makeClient { _ in (200, Fixtures.data("health")) }
        let items = try await client.health()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.severity, .warning)
    }

    func testSeriesDecodesWithStatisticsAndImages() async throws {
        let client = makeClient { _ in (200, Fixtures.data("series")) }
        let series = try await client.series()
        XCTAssertEqual(series.count, 2)
        let first = series[0]
        XCTAssertEqual(first.title, "Example Show")
        XCTAssertEqual(first.seasons?.count, 2)
        XCTAssertEqual(first.statistics?.seasonCount, 2)
        XCTAssertEqual(first.imageURL(coverType: "poster"), "https://artworks.example/poster.jpg")
        // Series without a languageProfileId (v4-style) still decodes.
        XCTAssertNil(series[1].languageProfileId)
    }

    func testQueueDecodesAndComputesProgress() async throws {
        let client = makeClient { _ in (200, Fixtures.data("queue")) }
        let queue = try await client.queue()
        XCTAssertEqual(queue.totalRecords, 1)
        let item = try XCTUnwrap(queue.records.first)
        XCTAssertEqual(item.protocolName, "torrent")
        // (2147483648 - 536870912) / 2147483648 = 0.75
        XCTAssertEqual(item.progress, 0.75, accuracy: 0.001)
    }

    func testReleasesDecodeRejections() async throws {
        let client = makeClient { _ in (200, Fixtures.data("releases")) }
        let releases = try await client.releases(episodeId: 1001)
        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(releases[0].seeders, 120)
        XCTAssertEqual(releases[1].rejected, true)
        XCTAssertEqual(releases[1].rejections, ["Quality below cutoff"])
    }

    func testAddSeriesSendsExpectedPayload() async throws {
        var capturedBody: Data?
        var capturedMethod: String?
        let client = makeClient { request in
            capturedMethod = request.httpMethod
            // URLProtocol strips httpBody into httpBodyStream for some sessions;
            // capture from whichever is populated.
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (201, Fixtures.data("series")) // echo back something decodable
        }
        let lookup = SonarrSeries(id: 0, title: "New Show", year: 2024, tvdbId: 999, titleSlug: "new-show")
        let request = SonarrAddSeriesRequest(
            lookup: lookup,
            qualityProfileId: 1,
            languageProfileId: nil,
            rootFolderPath: "/tv"
        )
        _ = try? await client.addSeries(request)
        XCTAssertEqual(capturedMethod, "POST")
        let body = try XCTUnwrap(capturedBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "New Show")
        XCTAssertEqual(json?["qualityProfileId"] as? Int, 1)
        XCTAssertEqual(json?["rootFolderPath"] as? String, "/tv")
        XCTAssertNotNil(json?["addOptions"])
    }

    func testCommandRequestEncodesEpisodeSearch() async throws {
        var capturedBody: Data?
        let client = makeClient { request in
            capturedBody = request.httpBody ?? request.bodyStreamData()
            return (201, #"{"id": 7, "name": "EpisodeSearch", "status": "queued"}"#.data(using: .utf8)!)
        }
        let result = try await client.runCommand(.episodeSearch(episodeIds: [101, 102]))
        XCTAssertEqual(result.id, 7)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "EpisodeSearch")
        XCTAssertEqual((json?["episodeIds"] as? [Int]), [101, 102])
    }

    func testLanguageProfilesReturnsEmptyOn404() async throws {
        let client = makeClient { _ in (404, Data()) }
        let profiles = try await client.languageProfiles()
        XCTAssertTrue(profiles.isEmpty)
    }

    func testEditSeriesEncodesEditorPayload() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.editSeries(ids: [12], monitored: true, qualityProfileId: 5)
        XCTAssertEqual(method, "PUT")
        XCTAssertTrue(path?.hasSuffix("/series/editor") == true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["seriesIds"] as? [Int], [12])
        XCTAssertEqual(json?["monitored"] as? Bool, true)
        XCTAssertEqual(json?["qualityProfileId"] as? Int, 5)
        // No root-folder change → no rootFolderPath/moveFiles keys.
        XCTAssertNil(json?["rootFolderPath"])
        XCTAssertNil(json?["moveFiles"])
    }

    func testSetEpisodesMonitoredEncodesPayload() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.setEpisodesMonitored(ids: [101, 102], monitored: false)
        XCTAssertEqual(method, "PUT")
        XCTAssertTrue(path?.hasSuffix("/episode/monitor") == true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["episodeIds"] as? [Int], [101, 102])
        XCTAssertEqual(json?["monitored"] as? Bool, false)
    }

    func testUpdateSeriesPutsFullResourceToIdPath() async throws {
        var method: String?; var path: String?; var body: Data?
        let client = makeClient { request in
            method = request.httpMethod; path = request.url?.path
            body = request.httpBody ?? request.bodyStreamData()
            return (200, #"{"id":7,"title":"Example Show","monitored":false}"#.data(using: .utf8)!)
        }
        var series = SonarrSeries(id: 7, title: "Example Show")
        series.monitored = false
        series.seasons = [SonarrSeason(seasonNumber: 1, monitored: true)]
        _ = try await client.updateSeries(series)
        XCTAssertEqual(method, "PUT")
        XCTAssertTrue(path?.hasSuffix("/series/7") == true)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        XCTAssertEqual(json?["id"] as? Int, 7)
        XCTAssertEqual(json?["monitored"] as? Bool, false)
    }

    func testDownloadClientsDecode() async throws {
        var path: String?
        let client = makeClient { request in
            path = request.url?.path
            let body = #"[{"id":1,"name":"qBit","enable":true,"protocol":"torrent","implementation":"QBittorrent","priority":1},{"id":2,"name":"SAB","enable":false,"protocol":"usenet","implementation":"Sabnzbd","priority":2}]"#
            return (200, body.data(using: .utf8)!)
        }
        let clients = try await client.downloadClients()
        XCTAssertEqual(path, "/api/v3/downloadclient")
        XCTAssertEqual(clients.count, 2)
        XCTAssertEqual(clients[0].name, "qBit")
        XCTAssertEqual(clients[0].enable, true)
        XCTAssertEqual(clients[0].protocolName, "torrent")
        XCTAssertEqual(clients[1].enable, false)
    }

    func testSetDownloadClientEnabledRoundTripsPreservingFields() async throws {
        var putMethod: String?; var putPath: String?; var putBody: Data?
        let client = makeClient { request in
            if request.httpMethod == "GET" {
                let body = #"{"id":2,"name":"SAB","enable":true,"protocol":"usenet","fields":[{"name":"host","value":"x"}]}"#
                return (200, body.data(using: .utf8)!)
            }
            putMethod = request.httpMethod
            putPath = request.url?.path
            putBody = request.httpBody ?? request.bodyStreamData()
            return (200, Data())
        }
        try await client.setDownloadClientEnabled(id: 2, enabled: false)
        XCTAssertEqual(putMethod, "PUT")
        XCTAssertEqual(putPath, "/api/v3/downloadclient/2")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(putBody)) as? [String: Any]
        XCTAssertEqual(json?["enable"] as? Bool, false)
        XCTAssertEqual(json?["id"] as? Int, 2)
        XCTAssertNotNil(json?["fields"]) // unmapped fields survive the round-trip
    }
}

private extension URLRequest {
    /// Reads the body from `httpBodyStream` when `httpBody` is nil (URLProtocol
    /// converts bodies to streams).
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
