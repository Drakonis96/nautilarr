// swift-tools-version: 5.9
import PackageDescription

// NautilarrKit groups the platform-agnostic logic of the app into library
// targets so it can be unit-tested in isolation (via `swift test`) without
// needing the full Xcode app target. The SwiftUI app links these products.
let package = Package(
    name: "NautilarrKit",
    platforms: [
        // Raised to iOS 17 / macOS 14 to use Citadel (modern SwiftNIO SSH) for
        // the SSH terminal + SFTP browser. See README/CONTRIBUTING.
        .iOS(.v17),
        .macCatalyst(.v17),
        .macOS(.v14)
    ],
    products: [
        // Shared networking, models, security and connectivity primitives.
        .library(name: "NautilarrCore", targets: ["NautilarrCore"]),
        // Phase 1 media-management integrations (*arr family).
        .library(name: "SonarrKit", targets: ["SonarrKit"]),
        .library(name: "RadarrKit", targets: ["RadarrKit"]),
        .library(name: "LidarrKit", targets: ["LidarrKit"]),
        // Phase 2 download clients & requests.
        .library(name: "QBittorrentKit", targets: ["QBittorrentKit"]),
        .library(name: "SABnzbdKit", targets: ["SABnzbdKit"]),
        .library(name: "OverseerrKit", targets: ["OverseerrKit"]),
        .library(name: "NZBGetKit", targets: ["NZBGetKit"]),
        .library(name: "TransmissionKit", targets: ["TransmissionKit"]),
        .library(name: "DelugeKit", targets: ["DelugeKit"]),
        // Phase 3 monitoring & indexers.
        .library(name: "SSHKit", targets: ["SSHKit"]),
        .library(name: "TautulliKit", targets: ["TautulliKit"]),
        .library(name: "ProwlarrKit", targets: ["ProwlarrKit"]),
        .library(name: "BazarrKit", targets: ["BazarrKit"]),
        .library(name: "JellystatKit", targets: ["JellystatKit"]),
        .library(name: "UnraidKit", targets: ["UnraidKit"]),
        .library(name: "TorznabKit", targets: ["TorznabKit"])
    ],
    dependencies: [
        // Pure-Swift SSH (SwiftNIO SSH under the hood). SPM, no paid
        // entitlements — outbound TCP only. Used by SSHKit for the terminal,
        // SFTP browser and host stats.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", .upToNextMinor(from: "0.12.1")),
        // Direct dependency (same fork/range Citadel resolves) so SSHKit can use
        // `NIOSSHPublicKey` for host-key pinning (TOFU). SPM dedupes the package.
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0")
    ],
    targets: [
        .target(
            name: "NautilarrCore"
        ),
        .target(
            name: "SonarrKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "RadarrKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "LidarrKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "QBittorrentKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "SABnzbdKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "OverseerrKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "NZBGetKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "TransmissionKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "DelugeKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "SSHKit",
            dependencies: [
                "NautilarrCore",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ]
        ),
        .target(
            name: "TautulliKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "ProwlarrKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "BazarrKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "JellystatKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "UnraidKit",
            dependencies: ["NautilarrCore"]
        ),
        .target(
            name: "TorznabKit",
            dependencies: ["NautilarrCore"]
        ),
        .testTarget(
            name: "NautilarrCoreTests",
            dependencies: ["NautilarrCore"]
        ),
        .testTarget(
            name: "SonarrKitTests",
            dependencies: ["SonarrKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "RadarrKitTests",
            dependencies: ["RadarrKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "LidarrKitTests",
            dependencies: ["LidarrKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "QBittorrentKitTests",
            dependencies: ["QBittorrentKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SABnzbdKitTests",
            dependencies: ["SABnzbdKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "OverseerrKitTests",
            dependencies: ["OverseerrKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "NZBGetKitTests",
            dependencies: ["NZBGetKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TransmissionKitTests",
            dependencies: ["TransmissionKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DelugeKitTests",
            dependencies: ["DelugeKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TautulliKitTests",
            dependencies: ["TautulliKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ProwlarrKitTests",
            dependencies: ["ProwlarrKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BazarrKitTests",
            dependencies: ["BazarrKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SSHKitTests",
            dependencies: ["SSHKit", "NautilarrCore"]
        ),
        .testTarget(
            name: "JellystatKitTests",
            dependencies: ["JellystatKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "UnraidKitTests",
            dependencies: ["UnraidKit", "NautilarrCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TorznabKitTests",
            dependencies: ["TorznabKit", "NautilarrCore"]
        )
    ]
)
