import Foundation
import Combine
import NautilarrCore

/// Composition root holding the app's long-lived services. Injected into the
/// SwiftUI environment so any view can reach the stores it needs.
@MainActor
final class AppEnvironment: ObservableObject {
    let networkMonitor: NetworkMonitor
    let instanceStore: InstanceStore
    let settings: AppSettings
    let notifications: NotificationManager
    let backgroundRefresh: BackgroundRefreshManager
    let updateChecker = UpdateChecker()
    let appLock = AppLockManager()

    /// Active-download count shown as a badge on the Downloads tab. Updated by
    /// the Home and Downloads screens as they refresh.
    @Published var activeDownloadCount: Int = 0

    init() {
        let monitor = NetworkMonitor()
        monitor.start()
        let store = InstanceStore(monitor: monitor)
        let notifications = NotificationManager()

        self.networkMonitor = monitor
        self.instanceStore = store
        self.settings = AppSettings()
        self.notifications = notifications
        self.backgroundRefresh = BackgroundRefreshManager(instanceStore: store, notifications: notifications)
    }
}
