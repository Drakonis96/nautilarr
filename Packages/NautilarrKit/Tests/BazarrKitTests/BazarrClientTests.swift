import XCTest
@testable import BazarrKit
import NautilarrCore

final class BazarrClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.setHandler(nil); super.tearDown() }

    private func makeClient(route: @escaping (URLRequest) -> (Int, Data)) -> BazarrClient {
        MockURLProtocol.setHandler { request in
            let (status, data) = route(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, data)
        }
        let api = APIClient(
            baseURLProvider: { [URL(string: "http://bazarr.test:6767")!] },
            authorizer: APIKeyHeaderAuthorizer(headerName: "X-Api-Key", apiKey: "KEY"),
            sessionConfiguration: MockURLProtocol.sessionConfiguration()
        )
        return BazarrClient(api: api)
    }

    func testBadgesDecode() async throws {
        let client = makeClient { _ in (200, Fixtures.data("badges")) }
        let badges = try await client.badges()
        XCTAssertEqual(badges.episodes, 12)
        XCTAssertEqual(badges.movies, 3)
        XCTAssertEqual(badges.providers, 5)
    }

    func testSystemStatusUnwrapsData() async throws {
        var apiKey: String?
        let client = makeClient { request in
            apiKey = request.value(forHTTPHeaderField: "X-Api-Key")
            return (200, #"{"data":{"bazarr_version":"1.4.3","operating_system":"Linux"}}"#.data(using: .utf8)!)
        }
        let status = try await client.systemStatus()
        XCTAssertEqual(apiKey, "KEY")
        XCTAssertEqual(status.bazarrVersion, "1.4.3")
    }

    func testWantedEpisodesUnwrapDataAndMapKeys() async throws {
        var path: String?
        let client = makeClient { request in
            path = request.url?.path
            let body = #"{"data":[{"seriesTitle":"Demo","episodeTitle":"Pilot","episode_number":"1x01","sonarrSeriesId":4,"sonarrEpisodeId":99,"missing_subtitles":[{"name":"English","code2":"en"}]}],"total":1}"#
            return (200, body.data(using: .utf8)!)
        }
        let wanted = try await client.wantedEpisodes()
        XCTAssertEqual(path, "/api/episodes/wanted")
        XCTAssertEqual(wanted.count, 1)
        XCTAssertEqual(wanted[0].sonarrEpisodeId, 99)
        XCTAssertEqual(wanted[0].episodeNumber, "1x01")
        XCTAssertEqual(wanted[0].missingSubtitles?.first?.code2, "en")
    }

    func testWantedMoviesUnwrapData() async throws {
        let client = makeClient { _ in
            (200, #"{"data":[{"title":"Demo Movie","radarrId":7,"missing_subtitles":[{"name":"Spanish","code2":"es"}]}],"total":1}"#.data(using: .utf8)!)
        }
        let wanted = try await client.wantedMovies()
        XCTAssertEqual(wanted.count, 1)
        XCTAssertEqual(wanted[0].radarrId, 7)
        XCTAssertEqual(wanted[0].missingSubtitles?.first?.code2, "es")
    }
}
