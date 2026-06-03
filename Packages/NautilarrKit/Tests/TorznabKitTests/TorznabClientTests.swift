import XCTest
@testable import TorznabKit

final class TorznabClientTests: XCTestCase {
    func testExtractsServerTitle() {
        let xml = #"<?xml version="1.0"?><caps><server title="NZBHydra2" version="5.0"/><categories><category id="2000" name="Movies"/><category id="5000" name="TV"/></categories></caps>"#
        XCTAssertEqual(TorznabClient.attribute("title", inElement: "server", of: xml), "NZBHydra2")
    }

    func testExtractsErrorDescription() {
        let xml = #"<error code="100" description="Incorrect user credentials"/>"#
        XCTAssertEqual(TorznabClient.attribute("description", inElement: "error", of: xml), "Incorrect user credentials")
    }

    func testMissingAttributeReturnsNil() {
        let xml = "<caps><server/></caps>"
        XCTAssertNil(TorznabClient.attribute("title", inElement: "server", of: xml))
    }

    func testFeedParserExtractsResults() {
        let xml = #"""
        <?xml version="1.0"?>
        <rss xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel>
          <item>
            <title>Example Movie 2024 1080p</title>
            <guid>abc-123</guid>
            <link>http://host/dl/abc.torrent</link>
            <size>1500000000</size>
            <enclosure url="http://host/dl/abc.torrent" length="1500000000" type="application/x-bittorrent"/>
            <torznab:attr name="seeders" value="42"/>
            <jackettindexer id="x">MyTracker</jackettindexer>
          </item>
          <item>
            <title>Another Release</title>
            <torznab:attr name="seeders" value="5"/>
          </item>
        </channel></rss>
        """#
        let results = TorznabFeedParser(data: Data(xml.utf8)).parse()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Example Movie 2024 1080p")
        XCTAssertEqual(results[0].seeders, 42)
        XCTAssertEqual(results[0].size, 1_500_000_000)
        XCTAssertEqual(results[0].indexer, "MyTracker")
        XCTAssertEqual(results[0].guid, "abc-123")
        XCTAssertEqual(results[0].link, "http://host/dl/abc.torrent")
        XCTAssertEqual(results[1].seeders, 5)
    }
}
