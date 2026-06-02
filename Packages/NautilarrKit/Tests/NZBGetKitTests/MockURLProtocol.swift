import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let lock = NSLock()
    static func setHandler(_ handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock(); defer { lock.unlock() }; requestHandler = handler
    }
    static func handler() -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock(); defer { lock.unlock() }; return requestHandler
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
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

enum Fixtures {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json") else {
            fatalError("Missing fixture \(name).json")
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }
}

extension URLRequest {
    func bodyText() -> String {
        if let body = httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); let size = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
