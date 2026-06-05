import Foundation
import UserNotifications
import Combine

/// Categories of local notification the user can toggle per the spec. No remote
/// push is used — everything is a local notification scheduled by the app while
/// it is running or during a background refresh.
enum NotificationEvent: String, CaseIterable, Identifiable, Codable {
    case grabbed
    case imported
    case stuckImport
    case healthWarning
    case pendingRequest
    case newStream

    var id: String { rawValue }
    var title: String {
        switch self {
        case .grabbed: return "Release grabbed"
        case .imported: return "Download imported"
        case .stuckImport: return "Import needs attention"
        case .healthWarning: return "Health warning"
        case .pendingRequest: return "Pending request"
        case .newStream: return "New stream"
        }
    }
}

/// Wraps `UNUserNotificationCenter` for permission handling and posting local
/// notifications. Remote push is intentionally unsupported (it would require a
/// paid APNs entitlement, incompatible with free-certificate distribution).
@MainActor
final class NotificationManager: ObservableObject {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    /// Per-event toggles, persisted in `UserDefaults`.
    func isEnabled(_ event: NotificationEvent) -> Bool {
        UserDefaults.standard.object(forKey: key(event)) as? Bool ?? true
    }
    func setEnabled(_ enabled: Bool, for event: NotificationEvent) {
        objectWillChange.send()
        UserDefaults.standard.set(enabled, forKey: key(event))
    }
    private func key(_ event: NotificationEvent) -> String { "notify.\(event.rawValue)" }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    /// Posts a local notification immediately, if the event type is enabled.
    func post(event: NotificationEvent, title: String, body: String) async {
        guard isEnabled(event) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(event.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
