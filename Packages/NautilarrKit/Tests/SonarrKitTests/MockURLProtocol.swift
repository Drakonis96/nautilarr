import Foundation

/// Local copy of the mock protocol for the SonarrKit test target (test targets
/// can't import each other).
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let lock = NSLock()

    static func setHandler(_ handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock(); defer { lock.unlock() }
        requestHandler = handler
    }
    static func handler() -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock(); defer { lock.unlock() }
        return requestHandler
    }
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocol.handler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

enum Fixtures {
    /// Loads a JSON fixture bundled with the test target.
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json") else {
            fatalError("Missing fixture \(name).json")
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }
}
