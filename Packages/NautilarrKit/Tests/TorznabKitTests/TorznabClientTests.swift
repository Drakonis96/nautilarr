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
}
