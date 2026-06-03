import Foundation
import BackgroundTasks
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit
import OverseerrKit
import TautulliKit
import JellystatKit

/// Coordinates periodic polling of services while the app is backgrounded,
/// using `BGAppRefreshTask`. On meaningful changes it posts a local
/// notification. This is the only mechanism available without a paid push
/// entitlement, and the OS limits how often refresh tasks run.
///
/// De-duplication state is persisted in `UserDefaults` so a notification isn't
/// repeated across the separate process launches the OS uses for background
/// tasks (the manager instance itself is short-lived).
@MainActor
final class BackgroundRefreshManager {
    static let refreshTaskIdentifier = "com.drakonis96.nautilarr.refresh"

    private let instanceStore: InstanceStore
    private let notifications: NotificationManager
    private let defaults = UserDefaults.standard
    /// Cap notifications posted per run so a backlog can't spam the user.
    private let maxPerRun = 6

    init(instanceStore: InstanceStore, notifications: NotificationManager) {
        self.instanceStore = instanceStore
        self.notifications = notifications
    }

    /// Schedules the next background refresh (~30 min out; the OS decides the
    /// actual time). Must be called at least once (on launch / when backgrounding)
    /// or the OS never runs the task.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Polls configured services and posts notifications for new health
    /// warnings, grabbed/imported episodes and pending requests. Returns `true`
    /// when it completes.
    @discardableResult
    func performRefresh() async -> Bool {
        var budget = maxPerRun
        await pollHealth(budget: &budget)
        await pollSonarrHistory(budget: &budget)
        await pollPendingRequests(budget: &budget)
        await pollStreams(budget: &budget)
        return true
    }

    // MARK: - Health warnings

    private func pollHealth(budget: inout Int) async {
        for instance in instanceStore.instances(ofType: .sonarr) {
            guard let client = instanceStore.sonarrClient(for: instance) else { continue }
            let issues = (try? await client.health())?
                .filter { $0.severity == .warning || $0.severity == .error }
                .map { ($0.message, $0.severity == .error) } ?? []
            await notifyHealth(issues, instanceName: instance.name, budget: &budget)
        }
        for instance in instanceStore.instances(ofType: .radarr) {
            guard let client = instanceStore.radarrClient(for: instance) else { continue }
            let issues = (try? await client.health())?
                .filter { $0.severity == .warning || $0.severity == .error }
                .map { ($0.message, $0.severity == .error) } ?? []
            await notifyHealth(issues, instanceName: instance.name, budget: &budget)
        }
        for instance in instanceStore.instances(ofType: .lidarr) {
            guard let client = instanceStore.lidarrClient(for: instance) else { continue }
            let issues = (try? await client.health())?
                .filter { $0.severity == .warning || $0.severity == .error }
                .map { ($0.message, $0.severity == .error) } ?? []
            await notifyHealth(issues, instanceName: instance.name, budget: &budget)
        }
    }

    private func notifyHealth(_ issues: [(message: String?, isError: Bool)], instanceName: String, budget: inout Int) async {
        var seen = stringSet(forKey: "notify.health")
        for issue in issues where budget > 0 {
            let key = "\(instanceName)|\(issue.message ?? "")"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            budget -= 1
            await notifications.post(
                event: .healthWarning,
                title: "\(instanceName): \(issue.isError ? "Error" : "Warning")",
                body: issue.message ?? "A health check reported an issue."
            )
        }
        // Keep the set bounded.
        setStringSet(Array(seen.suffix(200)), forKey: "notify.health")
    }

    // MARK: - Grabbed / imported (Sonarr history diff)

    private func pollSonarrHistory(budget: inout Int) async {
        for instance in instanceStore.instances(ofType: .sonarr) {
            guard let client = instanceStore.sonarrClient(for: instance) else { continue }
            guard let history = try? await client.history(pageSize: 30) else { continue }
            let records = history.records.sorted { $0.id < $1.id }
            guard let maxId = records.map(\.id).max() else { continue }

            let cursorKey = "notify.sonarrHistory.\(instance.id.uuidString)"
            // First time we see this instance: record the position, don't flood.
            guard defaults.object(forKey: cursorKey) != nil else {
                defaults.set(maxId, forKey: cursorKey)
                continue
            }
            let cursor = defaults.integer(forKey: cursorKey)
            for record in records where record.id > cursor && budget > 0 {
                let title = record.series?.title ?? record.episode?.title ?? "Episode"
                switch record.eventType?.lowercased() {
                case "grabbed":
                    budget -= 1
                    await notifications.post(event: .grabbed, title: "Grabbed",
                                             body: "\(title) was sent to your download client.")
                case "downloadfolderimported":
                    budget -= 1
                    await notifications.post(event: .imported, title: "Imported",
                                             body: "\(title) finished downloading and was imported.")
                default:
                    break
                }
            }
            defaults.set(maxId, forKey: cursorKey)
        }
    }

    // MARK: - Pending requests (Overseerr / Jellyseerr)

    private func pollPendingRequests(budget: inout Int) async {
        for instance in instanceStore.instances(ofType: .overseerr) {
            guard let client = instanceStore.overseerrClient(for: instance) else { continue }
            guard let page = try? await client.requests(take: 30, filter: "pending") else { continue }
            let pending = page.results
            let currentIDs = Set(pending.map(\.id))
            var notified = intSet(forKey: "notify.requests")
            for request in pending where budget > 0 {
                guard !notified.contains(request.id) else { continue }
                notified.insert(request.id)
                budget -= 1
                let who = request.requestedBy?.name
                let what = request.mediaType == "tv" ? "series" : "movie"
                await notifications.post(
                    event: .pendingRequest,
                    title: "New request",
                    body: who.map { "\($0) requested a \(what)." } ?? "A new \(what) request is pending."
                )
            }
            // Forget requests no longer pending so re-requests notify again.
            setIntSet(Array(notified.intersection(currentIDs)), forKey: "notify.requests")
        }
    }

    // MARK: - New streams (Tautulli / Jellystat)

    private func pollStreams(budget: inout Int) async {
        var notified = stringSet(forKey: "notify.streams")
        var active = Set<String>()

        for instance in instanceStore.instances(ofType: .tautulli) {
            guard let client = instanceStore.tautulliClient(for: instance) else { continue }
            guard let activity = try? await client.activity() else { continue }
            for session in activity.sessions {
                let key = "tautulli|\(instance.id.uuidString)|\(session.sessionKey ?? session.displayTitle)"
                active.insert(key)
                guard !notified.contains(key), budget > 0 else { continue }
                notified.insert(key); budget -= 1
                await notifications.post(
                    event: .newStream, title: "Now playing",
                    body: [session.user, session.displayTitle].compactMap { $0 }.joined(separator: " · ")
                )
            }
        }
        for instance in instanceStore.instances(ofType: .jellystat) {
            guard let client = instanceStore.jellystatClient(for: instance) else { continue }
            guard let sessions = try? await client.sessions() else { continue }
            for session in sessions {
                let key = "jellystat|\(instance.id.uuidString)|\(session.id)"
                active.insert(key)
                guard !notified.contains(key), budget > 0 else { continue }
                notified.insert(key); budget -= 1
                await notifications.post(
                    event: .newStream, title: "Now playing",
                    body: [session.userName, session.displayTitle].compactMap { $0 }.joined(separator: " · ")
                )
            }
        }
        // Keep only still-active sessions so a stream that stops then restarts
        // notifies again.
        setStringSet(Array(notified.intersection(active)), forKey: "notify.streams")
    }

    // MARK: - UserDefaults helpers

    private func stringSet(forKey key: String) -> Set<String> {
        Set((defaults.array(forKey: key) as? [String]) ?? [])
    }
    private func setStringSet(_ values: [String], forKey key: String) {
        defaults.set(values, forKey: key)
    }
    private func intSet(forKey key: String) -> Set<Int> {
        Set((defaults.array(forKey: key) as? [Int]) ?? [])
    }
    private func setIntSet(_ values: [Int], forKey key: String) {
        defaults.set(values, forKey: key)
    }
}
