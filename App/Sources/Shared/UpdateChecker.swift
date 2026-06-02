import Foundation
import Combine

/// An available newer release on GitHub.
struct UpdateInfo: Equatable, Identifiable {
    let version: String
    let url: URL          // macOS asset if present, else the release page
    let pageURL: URL      // the release page (for "release notes")
    let notes: String?
    var id: String { version }
}

/// Checks the GitHub Releases API for a newer version of Nautilarr. On macOS the
/// app is distributed as an ad-hoc-signed `.app` (no App Store / AltStore), so it
/// can't silently self-update; instead this surfaces a prompt with a download
/// link. Only runs on Mac Catalyst (iOS updates come through AltStore).
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var available: UpdateInfo?

    private static let repo = "drakonis96/nautilarr"
    private var didCheck = false

    /// Current app version, e.g. "0.1.0".
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Checks once per launch (Mac only). Safe to call repeatedly.
    func checkOnLaunch() async {
        #if targetEnvironment(macCatalyst)
        guard !didCheck else { return }
        didCheck = true
        await check()
        #endif
    }

    func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
        else { return }

        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard Self.isNewer(latest, than: Self.currentVersion) else { return }

        let asset = release.assets?.first { $0.name.lowercased().contains("macos") }
        guard let page = URL(string: release.htmlURL) else { return }
        available = UpdateInfo(
            version: latest,
            url: asset?.browserDownloadURL ?? page,
            pageURL: page,
            notes: release.body
        )
    }

    /// Numeric, component-wise version comparison ("0.10.0" > "0.9.9").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [Asset]?

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}
