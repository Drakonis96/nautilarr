import SwiftUI
import UserNotifications

/// Local-notification preferences. Explains the free-certificate limitation
/// (no remote push) up front.
struct NotificationSettingsView: View {
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        Form {
            Section {
                switch notifications.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .denied:
                    Label("Notifications denied — enable them in System Settings.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                default:
                    Button("Enable notifications") {
                        Task { await notifications.requestAuthorization() }
                    }
                }
            } footer: {
                Text("Nautilarr uses local notifications only. Push notifications while the app is closed are not possible with free-certificate distribution.")
            }
            .tintedCards()

            Section("Alert me about") {
                ForEach(NotificationEvent.allCases) { event in
                    Toggle(event.title, isOn: Binding(
                        get: { notifications.isEnabled(event) },
                        set: { notifications.setEnabled($0, for: event) }
                    ))
                }
            }
            .tintedCards()
        }
        .navigationTitle("Notifications")
        .task { await notifications.refreshAuthorizationStatus() }
    }
}
