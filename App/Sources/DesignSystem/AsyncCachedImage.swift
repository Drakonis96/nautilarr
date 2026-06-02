import SwiftUI
import NautilarrCore

/// An async image view backed by `ImageCache` (memory + disk). Used for posters
/// and cover art. Falls back to a placeholder while loading or on failure.
struct AsyncCachedImage<Placeholder: View>: View {
    let url: URL?
    var headers: [String: String] = [:]
    var allowSelfSignedHosts: Set<String> = []
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var imageData: Data?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let imageData, let platformImage = PlatformImage(data: imageData) {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await ImageCache.shared.data(for: url, headers: headers, allowSelfSignedHosts: allowSelfSignedHosts)
            await MainActor.run { self.imageData = data }
        } catch {
            // Leave placeholder in place on failure.
        }
    }
}

extension AsyncCachedImage where Placeholder == AnyView {
    init(url: URL?, headers: [String: String] = [:], allowSelfSignedHosts: Set<String> = []) {
        self.url = url
        self.headers = headers
        self.allowSelfSignedHosts = allowSelfSignedHosts
        self.placeholder = {
            AnyView(
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
            )
        }
    }
}

// MARK: - Cross-platform image bridge (UIImage is available on Catalyst too)

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif
