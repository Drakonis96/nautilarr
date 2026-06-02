import Foundation

/// A `URLProtocol` that intercepts requests and returns canned responses, so
/// networking can be tested without a live server.
final class MockURLProtocol: URLProtocol {
    /// Handler invoked for every intercepted request. Set before each test.
    /// Guarded by a lock because `URLSession` may dispatch on multiple queues.
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

    /// Builds a `URLSessionConfiguration` wired to this protocol.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
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

extension HTTPURLResponse {
    /// Convenience for building a response in tests.
    static func make(url: URL, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
