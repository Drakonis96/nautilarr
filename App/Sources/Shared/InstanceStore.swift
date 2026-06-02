import Foundation
import Combine
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

/// The single source of truth for configured service instances.
///
/// - Instances (non-secret) are persisted as JSON under Application Support.
/// - Credentials (secret) are persisted in the Keychain via `CredentialStore`.
/// - Builds typed service clients on demand, wired to the shared
///   `NetworkMonitor` for LAN/WAN failover.
@MainActor
final class InstanceStore: ObservableObject {
    /// All instances across every network.
    @Published private(set) var instances: [ServiceInstance] = []
    /// All configured network profiles (always at least one).
    @Published private(set) var networks: [ServiceNetwork] = []
    /// The currently-selected network; the whole app reflects only its services.
    /// Persistence is explicit (not in a `didSet`) so the temporary value used
    /// during `init` can't clobber the saved selection before `load()` reads it.
    @Published var activeNetworkID: UUID

    private func persistActiveNetwork() {
        UserDefaults.standard.set(activeNetworkID.uuidString, forKey: "activeNetworkID")
    }

    private let credentials = CredentialStore()
    private let monitor: NetworkMonitor
    private let fileURL: URL
    private let networksURL: URL

    init(monitor: NetworkMonitor) {
        self.monitor = monitor
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nautilarr", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.fileURL = support.appendingPathComponent("instances.json")
        self.networksURL = support.appendingPathComponent("networks.json")
        // Temporary value; replaced in load() once networks are known.
        self.activeNetworkID = UUID()
        load()
    }

    // MARK: - Networks

    var activeNetwork: ServiceNetwork? { networks.first { $0.id == activeNetworkID } }
    var instancesInActiveNetwork: [ServiceInstance] { instances.filter { $0.networkID == activeNetworkID } }

    func addNetwork(named name: String) {
        let network = ServiceNetwork(name: name)
        networks.append(network)
        activeNetworkID = network.id
        persistNetworks(); persistActiveNetwork()
    }

    func renameNetwork(_ id: UUID, to name: String) {
        guard let index = networks.firstIndex(where: { $0.id == id }) else { return }
        networks[index].name = name
        persistNetworks()
    }

    /// Deletes a network and all of its instances (and their credentials).
    /// Refuses to delete the last remaining network.
    func deleteNetwork(_ id: UUID) {
        guard networks.count > 1 else { return }
        instances.filter { $0.networkID == id }.forEach {
            try? credentials.delete(for: $0.id)
            try? credentials.deleteProxyCredential(for: $0.id)
        }
        instances.removeAll { $0.networkID == id }
        networks.removeAll { $0.id == id }
        if activeNetworkID == id, let first = networks.first { activeNetworkID = first.id }
        persist(); persistNetworks(); persistActiveNetwork()
    }

    func selectNetwork(_ id: UUID) {
        guard networks.contains(where: { $0.id == id }) else { return }
        activeNetworkID = id
        persistActiveNetwork()
    }

    // MARK: - CRUD

    /// Instances of a type **within the active network** — the app-facing view.
    func instances(ofType type: ServiceType) -> [ServiceInstance] {
        instances.filter { $0.type == type && $0.networkID == activeNetworkID }
    }

    func add(_ instance: ServiceInstance, credential: Credential) {
        var instance = instance
        if instance.networkID == nil { instance.networkID = activeNetworkID }
        instances.append(instance)
        try? credentials.save(credential, for: instance.id)
        persist()
    }

    func update(_ instance: ServiceInstance, credential: Credential?) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            var updated = instance
            // The editor doesn't carry networkID; preserve the existing one so
            // an edited instance doesn't drop out of its network.
            if updated.networkID == nil { updated.networkID = instances[index].networkID ?? activeNetworkID }
            instances[index] = updated
        }
        if let credential { try? credentials.save(credential, for: instance.id) }
        persist()
    }

    func remove(_ instance: ServiceInstance) {
        instances.removeAll { $0.id == instance.id }
        try? credentials.delete(for: instance.id)
        try? credentials.deleteProxyCredential(for: instance.id)
        persist()
    }

    func credential(for instance: ServiceInstance) -> Credential {
        (try? credentials.credential(for: instance.id)) ?? .none
    }

    // MARK: - Reverse-proxy Basic Auth

    /// The optional HTTP Basic Auth credential for a reverse proxy in front of
    /// the service (stored securely, separate from the service's own credential).
    func proxyCredential(for instance: ServiceInstance) -> Credential {
        ((try? credentials.proxyCredential(for: instance.id)) ?? nil) ?? .none
    }

    /// Saves (or clears, when empty) the reverse-proxy Basic Auth credential.
    func setProxyCredential(_ credential: Credential, for instance: ServiceInstance) {
        if credential.isEmpty {
            try? credentials.deleteProxyCredential(for: instance.id)
        } else {
            try? credentials.saveProxyCredential(credential, for: instance.id)
        }
    }

    /// Returns a copy of `instance` with the stored reverse-proxy Basic Auth
    /// header merged into its custom headers — **in memory only**, so the secret
    /// is attached to outgoing requests (via `APIClient`'s `extraHeaders`) but
    /// never persisted alongside the instance. No-op when no proxy credential is
    /// set; an explicit user-set `Authorization` header takes precedence.
    func withProxyAuth(_ instance: ServiceInstance) -> ServiceInstance {
        guard let header = proxyCredential(for: instance).basicAuthHeaderValue else { return instance }
        var copy = instance
        if copy.customHeaders["Authorization"] == nil {
            copy.customHeaders["Authorization"] = header
        }
        return copy
    }

    /// Whether secrets are stored in the system Keychain (`true`) or the
    /// on-device file fallback (`false`, used when the Keychain is unavailable).
    var secretsUseKeychain: Bool { credentials.usesKeychain }

    // MARK: - Client factories

    /// Builds a Sonarr client for an instance, or `nil` if the instance is not a
    /// Sonarr service.
    func sonarrClient(for instance: ServiceInstance) -> SonarrClient? {
        guard instance.type == .sonarr else { return nil }
        return SonarrClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func radarrClient(for instance: ServiceInstance) -> RadarrClient? {
        guard instance.type == .radarr else { return nil }
        return RadarrClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func lidarrClient(for instance: ServiceInstance) -> LidarrClient? {
        guard instance.type == .lidarr else { return nil }
        return LidarrClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func qbittorrentClient(for instance: ServiceInstance) -> QBittorrentClient? {
        guard instance.type == .qbittorrent else { return nil }
        return QBittorrentClient(instance: withProxyAuth(instance), credential: credential(for: instance))
    }

    func sabnzbdClient(for instance: ServiceInstance) -> SABnzbdClient? {
        guard instance.type == .sabnzbd else { return nil }
        return SABnzbdClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func overseerrClient(for instance: ServiceInstance) -> OverseerrClient? {
        guard instance.type == .overseerr else { return nil }
        return OverseerrClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func nzbgetClient(for instance: ServiceInstance) -> NZBGetClient? {
        guard instance.type == .nzbget else { return nil }
        return NZBGetClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func transmissionClient(for instance: ServiceInstance) -> TransmissionClient? {
        guard instance.type == .transmission else { return nil }
        return TransmissionClient(instance: withProxyAuth(instance), credential: credential(for: instance))
    }

    func delugeClient(for instance: ServiceInstance) -> DelugeClient? {
        guard instance.type == .deluge else { return nil }
        return DelugeClient(instance: withProxyAuth(instance), credential: credential(for: instance))
    }

    func tautulliClient(for instance: ServiceInstance) -> TautulliClient? {
        guard instance.type == .tautulli else { return nil }
        return TautulliClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func prowlarrClient(for instance: ServiceInstance) -> ProwlarrClient? {
        guard instance.type == .prowlarr else { return nil }
        return ProwlarrClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func bazarrClient(for instance: ServiceInstance) -> BazarrClient? {
        guard instance.type == .bazarr else { return nil }
        return BazarrClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func sshSession(for instance: ServiceInstance, timeout: TimeInterval = 30) -> SSHSession? {
        guard instance.type == .ssh else { return nil }
        let creds = credentials
        let id = instance.id
        return SSHSession(
            instance: instance, credential: credential(for: instance), timeout: timeout,
            // Read the pinned key live, so trusting it mid-session lets the very
            // next connect succeed without recreating the session.
            knownHostKeyProvider: { creds.sshHostKey(for: id) }
        )
    }

    /// Pins an SSH host key after the user verified its fingerprint.
    func trustSSHHostKey(_ key: Data, for instance: ServiceInstance) {
        credentials.saveSSHHostKey(key, for: instance.id)
    }

    /// Forgets the pinned SSH host key (use after deliberately rebuilding a server).
    func resetSSHHostKey(for instance: ServiceInstance) {
        credentials.deleteSSHHostKey(for: instance.id)
    }

    /// Forgets the pinned TLS certificate(s) for an instance's hosts (use after
    /// deliberately regenerating a self-signed certificate).
    func resetPinnedCertificates(for instance: ServiceInstance) {
        for host in instance.candidateBaseURLs().compactMap({ $0.host }) {
            credentials.deleteTLSPin(host: host)
        }
    }

    func jellystatClient(for instance: ServiceInstance) -> JellystatClient? {
        guard instance.type == .jellystat else { return nil }
        return JellystatClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func unraidClient(for instance: ServiceInstance) -> UnraidClient? {
        guard instance.type == .unraid else { return nil }
        return UnraidClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    func torznabClient(for instance: ServiceInstance) -> TorznabClient? {
        guard instance.type == .nzbhydra2 || instance.type == .jackett else { return nil }
        return TorznabClient(instance: withProxyAuth(instance), credential: credential(for: instance), monitor: monitor)
    }

    /// Headers needed to fetch images served behind a service's auth, combining
    /// custom headers with the API key (when header-based).
    func imageHeaders(for instance: ServiceInstance) -> [String: String] {
        var headers = withProxyAuth(instance).customHeaders
        if case let .apiKeyHeader(name) = instance.type.authenticationKind,
           let key = credential(for: instance).apiKeyValue {
            headers[name] = key
        }
        return headers
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ServiceInstance].self, from: data) {
            instances = decoded
        }
        if let data = try? Data(contentsOf: networksURL),
           let decoded = try? JSONDecoder().decode([ServiceNetwork].self, from: data) {
            networks = decoded
        }

        // Ensure at least one network exists (creates the default on first run).
        if networks.isEmpty {
            networks = [ServiceNetwork(name: "Default Network")]
        }

        // Restore the active network, defaulting to the first.
        if let raw = UserDefaults.standard.string(forKey: "activeNetworkID"),
           let id = UUID(uuidString: raw), networks.contains(where: { $0.id == id }) {
            activeNetworkID = id
        } else {
            activeNetworkID = networks[0].id
        }

        // Migrate legacy/orphaned instances into the active network so they
        // remain visible (pre-Networks instances have a nil networkID).
        var migrated = false
        let validIDs = Set(networks.map(\.id))
        for index in instances.indices where !validIDs.contains(instances[index].networkID ?? UUID()) {
            instances[index].networkID = activeNetworkID
            migrated = true
        }
        if migrated { persist() }
        persistNetworks()
        persistActiveNetwork()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func persistNetworks() {
        guard let data = try? JSONEncoder().encode(networks) else { return }
        try? data.write(to: networksURL, options: .atomic)
    }

    // MARK: - Import / export

    /// A portable configuration bundle (networks + instances + their credentials).
    struct ConfigBundle: Codable {
        var version: Int = 2
        var instances: [ServiceInstance]
        var credentials: [String: Credential]
        var networks: [ServiceNetwork]?
        /// Optional reverse-proxy Basic Auth credentials, keyed by instance id
        /// (added later — older bundles simply omit it).
        var proxyCredentials: [String: Credential]?
    }

    /// Errors surfaced when importing a configuration bundle.
    enum ConfigImportError: LocalizedError {
        case passphraseRequired, wrongPassphrase
        var errorDescription: String? {
            switch self {
            case .passphraseRequired: return "This backup is encrypted. Enter the password used to create it."
            case .wrongPassphrase: return "Wrong password for this backup."
            }
        }
    }

    /// Exports the configuration (instances + credentials + networks) **encrypted**
    /// with the given passphrase, so the backup file is useless if leaked.
    func exportConfiguration(passphrase: String) -> Data? {
        var creds: [String: Credential] = [:]
        var proxyCreds: [String: Credential] = [:]
        for instance in instances {
            creds[instance.id.uuidString] = credential(for: instance)
            let proxy = proxyCredential(for: instance)
            if !proxy.isEmpty { proxyCreds[instance.id.uuidString] = proxy }
        }
        let bundle = ConfigBundle(instances: instances, credentials: creds, networks: networks,
                                  proxyCredentials: proxyCreds.isEmpty ? nil : proxyCreds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(bundle) else { return nil }
        return try? SecretCrypto.encrypt(json, passphrase: passphrase)
    }

    /// Imports a configuration bundle, replacing the current configuration.
    /// Accepts both the new encrypted backups (passphrase required) and legacy
    /// plaintext bundles.
    func importConfiguration(_ data: Data, passphrase: String?) throws {
        let json: Data
        if SecretCrypto.isEncrypted(data) {
            guard let passphrase, !passphrase.isEmpty else { throw ConfigImportError.passphraseRequired }
            do { json = try SecretCrypto.decrypt(data, passphrase: passphrase) }
            catch { throw ConfigImportError.wrongPassphrase }
        } else {
            json = data
        }
        let bundle = try JSONDecoder().decode(ConfigBundle.self, from: json)
        for instance in instances {
            try? credentials.delete(for: instance.id)
            try? credentials.deleteProxyCredential(for: instance.id)
        }
        instances = bundle.instances
        // Restore networks (v2+); older bundles fall back to the default network.
        if let importedNetworks = bundle.networks, !importedNetworks.isEmpty {
            networks = importedNetworks
        } else if networks.isEmpty {
            networks = [ServiceNetwork(name: "Default Network")]
        }
        let defaultID = networks[0].id
        let validIDs = Set(networks.map(\.id))
        for index in instances.indices where !validIDs.contains(instances[index].networkID ?? defaultID) {
            instances[index].networkID = defaultID
        }
        if !networks.contains(where: { $0.id == activeNetworkID }) { activeNetworkID = defaultID }
        for instance in bundle.instances {
            if let cred = bundle.credentials[instance.id.uuidString] {
                try credentials.save(cred, for: instance.id)
            }
            if let proxy = bundle.proxyCredentials?[instance.id.uuidString] {
                try? credentials.saveProxyCredential(proxy, for: instance.id)
            }
        }
        persist(); persistNetworks()
    }
}
