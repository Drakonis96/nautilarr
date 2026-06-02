import XCTest
@testable import SSHKit

final class SSHSessionTests: XCTestCase {
    func testFingerprintMatchesOpenSSHFormat() {
        // Known SHA-256 of "abc" = ba7816bf… ; base64 without padding, "SHA256:" prefix.
        let fp = SSHSession.fingerprint(of: Data("abc".utf8))
        XCTAssertEqual(fp, "SHA256:ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0")
        XCTAssertTrue(fp.hasPrefix("SHA256:"))
        XCTAssertFalse(fp.hasSuffix("="), "Fingerprint must be unpadded base64")
    }

    func testFingerprintIsStableAndKeyDependent() {
        let a = SSHSession.fingerprint(of: Data([0x01, 0x02, 0x03]))
        let b = SSHSession.fingerprint(of: Data([0x01, 0x02, 0x03]))
        let c = SSHSession.fingerprint(of: Data([0x09, 0x09]))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testBareHostUsesDefaultPort() {
        let r = SSHSession.parseHostPort("192.168.1.10", defaultPort: 22, explicitPort: nil)
        XCTAssertEqual(r.host, "192.168.1.10")
        XCTAssertEqual(r.port, 22)
    }

    func testExplicitInstancePortUsedWhenNoEmbeddedPort() {
        let r = SSHSession.parseHostPort("nas.local", defaultPort: 22, explicitPort: 2222)
        XCTAssertEqual(r.host, "nas.local")
        XCTAssertEqual(r.port, 2222)
    }

    func testEmbeddedPortOverridesEverything() {
        let r = SSHSession.parseHostPort("nas.local:2200", defaultPort: 22, explicitPort: 2222)
        XCTAssertEqual(r.host, "nas.local")
        XCTAssertEqual(r.port, 2200)
    }

    func testStripsSchemeAndPath() {
        let r = SSHSession.parseHostPort("ssh://nas.local:2022/some/path", defaultPort: 22, explicitPort: nil)
        XCTAssertEqual(r.host, "nas.local")
        XCTAssertEqual(r.port, 2022)
    }
}
