import Foundation
import Network
import Combine

/// A snapshot of the current network conditions.
public struct NetworkStatus: Sendable, Equatable {
    public var isOnline: Bool
    /// Cellular or personal-hotspot — typically off the home LAN.
    public var isExpensive: Bool
    /// Low Data Mode or similar.
    public var isConstrained: Bool
    /// Connected via Wi-Fi or wired ethernet (a precondition for the LAN host
    /// being reachable).
    public var usesWiFiOrEthernet: Bool

    public init(isOnline: Bool = false, isExpensive: Bool = false, isConstrained: Bool = false, usesWiFiOrEthernet: Bool = false) {
        self.isOnline = isOnline
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.usesWiFiOrEthernet = usesWiFiOrEthernet
    }

    /// Heuristic: when not on Wi-Fi/ethernet (or on an expensive link), the LAN
    /// host is unlikely to be reachable, so try the WAN/fallback host first.
    public var prefersFallbackFirst: Bool {
        !usesWiFiOrEthernet || isExpensive
    }

    public static let unknown = NetworkStatus(isOnline: true)
}

/// Observes connectivity with `NWPathMonitor` and publishes a `NetworkStatus`.
///
/// Used to choose the LAN vs. WAN host automatically. It is an
/// `ObservableObject` so SwiftUI can react, and exposes a thread-safe
/// `snapshot()` for use inside the networking layer's `@Sendable` closures.
public final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    @Published public private(set) var status: NetworkStatus = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.drakonis96.nautilarr.networkmonitor")
    private let lock = NSLock()
    private var _snapshot: NetworkStatus = .unknown

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let status = NetworkStatus(
                isOnline: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                usesWiFiOrEthernet: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            )
            self.lock.lock()
            self._snapshot = status
            self.lock.unlock()
            DispatchQueue.main.async { self.status = status }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    /// Thread-safe current value, safe to read from any queue.
    public func snapshot() -> NetworkStatus {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }

    deinit { monitor.cancel() }
}
