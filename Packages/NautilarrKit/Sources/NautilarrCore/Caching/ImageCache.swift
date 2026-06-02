import Foundation
import CryptoKit

/// A small two-tier (memory + disk) cache for poster/cover image data.
///
/// Stores raw `Data` rather than decoded images so it stays free of any UI
/// framework and remains testable. The SwiftUI layer decodes the data into a
/// platform image. Disk entries live under Caches (purgeable by the OS).
public actor ImageCache {
    public static let shared = ImageCache()

    private let memory = NSCache<NSString, NSData>()
    private let directory: URL
    private let fileManager = FileManager.default
    private let defaultSession: URLSession
    /// Sessions that trust self-signed certificates for a specific host set,
    /// keyed by the sorted host list. Mirrors `APIClient`'s trust handling so
    /// cover art loads from self-signed HTTPS instances too.
    private var trustedSessions: [String: URLSession] = [:]

    public init(
        subdirectory: String = "ImageCache",
        memoryLimitBytes: Int = 64 * 1024 * 1024,
        session: URLSession = .shared
    ) {
        memory.totalCostLimit = memoryLimitBytes
        self.defaultSession = session
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent(subdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func session(forSelfSignedHosts hosts: Set<String>) -> URLSession {
        guard !hosts.isEmpty else { return defaultSession }
        let key = hosts.sorted().joined(separator: ",")
        if let existing = trustedSessions[key] { return existing }
        let delegate = SelfSignedTrustDelegate(allowedHosts: hosts)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        trustedSessions[key] = session
        return session
    }

    /// Returns cached data for `url`, downloading and caching it on a miss.
    /// - Parameters:
    ///   - headers: per-instance auth (e.g. an API key) for covers served
    ///     behind authentication.
    ///   - allowSelfSignedHosts: hosts for which TLS validation is relaxed, so
    ///     covers from self-signed HTTPS servers load.
    public func data(
        for url: URL,
        headers: [String: String] = [:],
        allowSelfSignedHosts: Set<String> = []
    ) async throws -> Data {
        let key = Self.cacheKey(for: url)

        if let cached = memory.object(forKey: key as NSString) {
            return cached as Data
        }
        let fileURL = directory.appendingPathComponent(key)
        if let diskData = try? Data(contentsOf: fileURL) {
            memory.setObject(diskData as NSData, forKey: key as NSString, cost: diskData.count)
            return diskData
        }

        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session(forSelfSignedHosts: allowSelfSignedHosts).data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.server(statusCode: http.statusCode, body: nil)
        }

        memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        try? data.write(to: fileURL, options: .atomic)
        return data
    }

    /// Removes all cached image data from memory and disk.
    public func clear() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Total bytes currently held on disk (best-effort).
    public func diskUsageBytes() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    private static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
