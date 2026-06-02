import Foundation
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit
import QBittorrentKit
import SABnzbdKit
import OverseerrKit
import NZBGetKit
import TransmissionKit
import DelugeKit
import TautulliKit
import ProwlarrKit
import BazarrKit
import SSHKit
import JellystatKit
import UnraidKit
import TorznabKit

/// Tests reachability/authentication for an instance. Phase-1 services have
/// rich tests (version probe); others fall back to a generic reachability check.
enum ConnectionTester {
    struct Result {
        var success: Bool
        var message: String
    }

    static func test(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor?) async -> Result {
        switch instance.type {
        case .sonarr:
            let client = SonarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: "Connected — \(status.appName ?? "service") \(status.version ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .radarr:
            let client = RadarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: "Connected — \(status.appName ?? "service") \(status.version ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .lidarr:
            let client = LidarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: "Connected — \(status.appName ?? "service") \(status.version ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .qbittorrent:
            let client = QBittorrentClient(instance: instance, credential: credential)
            do {
                let version = try await client.version()
                return Result(success: true, message: "Connected — qBittorrent \(version.version).")
            } catch { return Result(success: false, message: describe(error)) }

        case .sabnzbd:
            let client = SABnzbdClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let version = try await client.version()
                return Result(success: true, message: "Connected — SABnzbd \(version.version ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .overseerr:
            let client = OverseerrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.status()
                return Result(success: true, message: "Connected — version \(status.version ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .nzbget:
            let client = NZBGetClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let version = try await client.version()
                return Result(success: true, message: "Connected — NZBGet \(version).")
            } catch { return Result(success: false, message: describe(error)) }

        case .transmission:
            let client = TransmissionClient(instance: instance, credential: credential)
            do {
                let version = try await client.version()
                return Result(success: true, message: "Connected — Transmission \(version).")
            } catch { return Result(success: false, message: describe(error)) }

        case .deluge:
            let client = DelugeClient(instance: instance, credential: credential)
            do {
                let version = try await client.version()
                return Result(success: true, message: "Connected — Deluge \(version).")
            } catch { return Result(success: false, message: describe(error)) }

        case .tautulli:
            let client = TautulliClient(instance: instance, credential: credential, monitor: monitor)
            do {
                // Validate via a payload-agnostic probe, then best-effort the count.
                try await client.ping()
                let count = (try? await client.activity().count) ?? 0
                return Result(success: true, message: "Connected — \(count) active stream(s).")
            } catch { return Result(success: false, message: describe(error)) }

        case .prowlarr:
            let client = ProwlarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: "Connected — \(status.appName ?? "Prowlarr") \(status.version ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .bazarr:
            let client = BazarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: "Connected — Bazarr \(status.bazarrVersion ?? "unknown").")
            } catch { return Result(success: false, message: describe(error)) }

        case .ssh:
            // Host-key pinning: read the pinned key (if any). On first contact the
            // session aborts before auth and surfaces the fingerprint to verify —
            // we never auto-trust here, so the password can't reach an impostor.
            let creds = CredentialStore()
            let id = instance.id
            let session = SSHSession(
                instance: instance, credential: credential, timeout: instance.timeout,
                knownHostKeyProvider: { creds.sshHostKey(for: id) }
            )
            do {
                let uname = try await session.run("uname -sr || echo connected")
                await session.disconnect()
                return Result(success: true, message: "Connected — \(uname.trimmingCharacters(in: .whitespacesAndNewlines)).")
            } catch let SSHSession.SSHError.hostKeyUnverified(fingerprint, _) {
                return Result(success: false, message: "Reachable, but this host isn't trusted yet. Open the SSH service and verify this fingerprint to connect:\n\(fingerprint)")
            } catch { return Result(success: false, message: describe(error)) }

        case .jellystat:
            let client = JellystatClient(instance: instance, credential: credential, monitor: monitor)
            do {
                try await client.testReachable()
                let count = (try? await client.sessions().count) ?? 0
                return Result(success: true, message: "Connected — \(count) active session(s).")
            } catch { return Result(success: false, message: describe(error)) }

        case .unraid:
            let client = UnraidClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let snapshot = try await client.snapshot()
                return Result(success: true, message: "Connected — array \(snapshot.array?.state ?? "unknown"), \(snapshot.runningContainers) container(s) running.")
            } catch { return Result(success: false, message: describe(error)) }

        case .nzbhydra2, .jackett:
            let client = TorznabClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let caps = try await client.capabilities()
                return Result(success: true, message: "Connected — \(caps.serverTitle ?? "indexer") (\(caps.categoryCount) categories).")
            } catch { return Result(success: false, message: describe(error)) }
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
