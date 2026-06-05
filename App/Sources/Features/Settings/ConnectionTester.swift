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
import StatainerKit

/// Tests reachability/authentication for an instance. Phase-1 services have
/// rich tests (version probe); others fall back to a generic reachability check.
enum ConnectionTester {
    struct Result {
        var success: Bool
        var message: String
    }

    static func test(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor?, proxyCredential: Credential = .none) async -> Result {
        // Merge the reverse-proxy Basic Auth header (if any) into a copy of the
        // instance so the test goes through the same proxy gate as live requests.
        let instance: ServiceInstance = {
            guard let header = proxyCredential.basicAuthHeaderValue else { return instance }
            var copy = instance
            if copy.customHeaders["Authorization"] == nil { copy.customHeaders["Authorization"] = header }
            return copy
        }()
        switch instance.type {
        case .sonarr:
            let client = SonarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: L("Connected — %@ %@.", status.appName ?? "service", status.version ?? "unknown"))
            } catch { return Result(success: false, message: describe(error)) }

        case .radarr:
            let client = RadarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: L("Connected — %@ %@.", status.appName ?? "service", status.version ?? "unknown"))
            } catch { return Result(success: false, message: describe(error)) }

        case .lidarr:
            let client = LidarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: L("Connected — %@ %@.", status.appName ?? "service", status.version ?? "unknown"))
            } catch { return Result(success: false, message: describe(error)) }

        case .qbittorrent:
            let client = QBittorrentClient(instance: instance, credential: credential)
            do {
                let version = try await client.version()
                return Result(success: true, message: L("Connected — qBittorrent %@.", version.version))
            } catch { return Result(success: false, message: describe(error)) }

        case .sabnzbd:
            let client = SABnzbdClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let version = try await client.version()
                return Result(success: true, message: L("Connected — SABnzbd %@.", version.version ?? "unknown"))
            } catch { return Result(success: false, message: describe(error)) }

        case .overseerr:
            let client = OverseerrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.status()
                return Result(success: true, message: L("Connected — version %@.", status.version ?? "unknown"))
            } catch { return Result(success: false, message: describe(error)) }

        case .nzbget:
            let client = NZBGetClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let version = try await client.version()
                return Result(success: true, message: L("Connected — NZBGet %@.", version))
            } catch { return Result(success: false, message: describe(error)) }

        case .transmission:
            let client = TransmissionClient(instance: instance, credential: credential)
            do {
                let version = try await client.version()
                return Result(success: true, message: L("Connected — Transmission %@.", version))
            } catch { return Result(success: false, message: describe(error)) }

        case .deluge:
            let client = DelugeClient(instance: instance, credential: credential)
            do {
                let version = try await client.version()
                return Result(success: true, message: L("Connected — Deluge %@.", version))
            } catch { return Result(success: false, message: describe(error)) }

        case .tautulli:
            let client = TautulliClient(instance: instance, credential: credential, monitor: monitor)
            do {
                // Validate via a payload-agnostic probe, then best-effort the count.
                try await client.ping()
                let count = (try? await client.activity().count) ?? 0
                return Result(success: true, message: L("Connected — %lld active stream(s).", count))
            } catch { return Result(success: false, message: describe(error)) }

        case .prowlarr:
            let client = ProwlarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: L("Connected — %@ %@.", status.appName ?? "Prowlarr", status.version ?? "unknown"))
            } catch { return Result(success: false, message: describe(error)) }

        case .bazarr:
            let client = BazarrClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let status = try await client.systemStatus()
                return Result(success: true, message: L("Connected — Bazarr %@.", status.bazarrVersion ?? "unknown"))
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
                return Result(success: true, message: L("Connected — %@.", uname.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch let SSHSession.SSHError.hostKeyUnverified(fingerprint, _) {
                return Result(success: false, message: L("Reachable, but this host isn't trusted yet. Open the SSH service and verify this fingerprint to connect:\n%@", fingerprint))
            } catch { return Result(success: false, message: describe(error)) }

        case .jellystat:
            let client = JellystatClient(instance: instance, credential: credential, monitor: monitor)
            do {
                try await client.testReachable()
                let count = (try? await client.sessions().count) ?? 0
                return Result(success: true, message: L("Connected — %lld active session(s).", count))
            } catch { return Result(success: false, message: describe(error)) }

        case .unraid:
            let client = UnraidClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let snapshot = try await client.snapshot()
                return Result(success: true, message: L("Connected — array %@, %lld container(s) running.", snapshot.array?.state ?? "unknown", snapshot.runningContainers))
            } catch { return Result(success: false, message: describe(error)) }

        case .nzbhydra2, .jackett:
            let client = TorznabClient(instance: instance, credential: credential, monitor: monitor)
            do {
                let caps = try await client.capabilities()
                return Result(success: true, message: L("Connected — %@ (%lld categories).", caps.serverTitle ?? "indexer", caps.categoryCount))
            } catch { return Result(success: false, message: describe(error)) }

        case .statainer:
            let client = StatainerClient(instance: instance, credential: credential, monitor: monitor)
            do {
                // Validate the token cheaply, then best-effort the container count.
                let ping = try await client.ping()
                let count = (try? await client.containers().count) ?? 0
                return Result(success: true, message: L("Connected — Statainer %@, %lld container(s).", ping.version ?? "", count))
            } catch { return Result(success: false, message: describe(error)) }
        }
    }

    /// Localised, formatted connection-test message (looks the key up in the
    /// app's `Localizable.strings`, then substitutes the arguments).
    private static func L(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: "connection test result"), arguments: args)
    }

    private static func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
