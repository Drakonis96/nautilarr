import Foundation
import BackgroundTasks
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit

/// Coordinates periodic polling of services while the app is backgrounded,
/// using `BGAppRefreshTask`. On meaningful changes (e.g. a new health warning),
/// it posts a local notification. This is the only mechanism available without
/// a paid push entitlement, and the OS limits how often refresh tasks run.
@MainActor
final class BackgroundRefreshManager {
    static let refreshTaskIdentifier = "com.drakonis96.nautilarr.refresh"

    private let instanceStore: InstanceStore
    private let notifications: NotificationManager
    /// Health messages already notified, to avoid duplicate alerts.
    private var notifiedHealthKeys: Set<String> = []

    init(instanceStore: InstanceStore, notifications: NotificationManager) {
        self.instanceStore = instanceStore
        self.notifications = notifications
    }

    /// Schedules the next background refresh (~30 min out; the OS decides the
    /// actual time).
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Polls all media-management instances for health and posts notifications
    /// for new warnings/errors. Returns `true` if it completed.
    @discardableResult
    func performRefresh() async -> Bool {
        for instance in instanceStore.instances(ofType: .sonarr) {
            guard let client = instanceStore.sonarrClient(for: instance) else { continue }
            let issues = (try? await client.health())?
                .filter { $0.severity == .warning || $0.severity == .error }
                .map { ($0.message, $0.severity == .error) } ?? []
            await notify(issues, instanceName: instance.name)
        }
        for instance in instanceStore.instances(ofType: .radarr) {
            guard let client = instanceStore.radarrClient(for: instance) else { continue }
            let issues = (try? await client.health())?
                .filter { $0.severity == .warning || $0.severity == .error }
                .map { ($0.message, $0.severity == .error) } ?? []
            await notify(issues, instanceName: instance.name)
        }
        for instance in instanceStore.instances(ofType: .lidarr) {
            guard let client = instanceStore.lidarrClient(for: instance) else { continue }
            let issues = (try? await client.health())?
                .filter { $0.severity == .warning || $0.severity == .error }
                .map { ($0.message, $0.severity == .error) } ?? []
            await notify(issues, instanceName: instance.name)
        }
        return true
    }

    /// Posts a de-duplicated notification for each new health issue.
    private func notify(_ issues: [(message: String?, isError: Bool)], instanceName: String) async {
        for issue in issues {
            let key = "\(instanceName)|\(issue.message ?? "")"
            guard !notifiedHealthKeys.contains(key) else { continue }
            notifiedHealthKeys.insert(key)
            await notifications.post(
                event: .healthWarning,
                title: "\(instanceName): \(issue.isError ? "Error" : "Warning")",
                body: issue.message ?? "A health check reported an issue."
            )
        }
    }
}
