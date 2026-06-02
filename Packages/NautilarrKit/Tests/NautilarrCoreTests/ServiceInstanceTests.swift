import XCTest
@testable import NautilarrCore

final class ServiceInstanceTests: XCTestCase {
    func testBareHostUsesDefaultPortAndScheme() {
        let instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "192.168.1.10")
        let url = instance.baseURL(for: instance.primaryHost)
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.10:8989")
    }

    func testHTTPSToggle() {
        var instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "nas.local")
        instance.useHTTPS = true
        let url = instance.baseURL(for: instance.primaryHost)
        XCTAssertEqual(url?.scheme, "https")
    }

    func testExplicitPortInHostOverridesDefault() {
        let instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "nas.local:9999")
        let url = instance.baseURL(for: instance.primaryHost)
        XCTAssertEqual(url?.port, 9999)
        XCTAssertEqual(url?.host, "nas.local")
    }

    func testFullURLPastedIsHonoured() {
        let instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "https://sonarr.example.com/sonarr")
        let url = instance.baseURL(for: instance.primaryHost)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "sonarr.example.com")
        XCTAssertEqual(url?.path, "/sonarr")
    }

    func testURLBaseAppended() {
        var instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "nas.local")
        instance.urlBase = "/sonarr"
        let url = instance.baseURL(for: instance.primaryHost)
        XCTAssertEqual(url?.path, "/sonarr")
    }

    func testCandidateOrderingAutomaticPrefersPrimary() {
        var instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "lan.local", fallbackHost: "wan.example.com")
        instance.hostSelection = .automatic
        let urls = instance.candidateBaseURLs(preferFallbackFirst: false)
        XCTAssertEqual(urls.first?.host, "lan.local")
        XCTAssertEqual(urls.last?.host, "wan.example.com")
    }

    func testCandidateOrderingPrefersFallbackWhenRequested() {
        let instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "lan.local", fallbackHost: "wan.example.com")
        let urls = instance.candidateBaseURLs(preferFallbackFirst: true)
        XCTAssertEqual(urls.first?.host, "wan.example.com")
    }

    func testForcePrimaryIgnoresFallback() {
        var instance = ServiceInstance(type: .sonarr, name: "S", primaryHost: "lan.local", fallbackHost: "wan.example.com")
        instance.hostSelection = .forcePrimary
        let urls = instance.candidateBaseURLs(preferFallbackFirst: true)
        XCTAssertEqual(urls.map(\.host), ["lan.local"])
    }

    func testDefaultPortMatchesServiceType() {
        XCTAssertEqual(ServiceType.radarr.defaultPort, 7878)
        XCTAssertEqual(ServiceType.sonarr.defaultPort, 8989)
    }
}
