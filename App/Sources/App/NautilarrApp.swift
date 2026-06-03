import SwiftUI

/// App entry point. A single SwiftUI lifecycle that runs on iOS, iPadOS and
/// macOS (via Mac Catalyst).
@main
struct NautilarrApp: App {
    @StateObject private var environment = AppEnvironment()

    init() {
        // Remove the hairline separator under navigation bars so the Home ocean
        // header meets the title seamlessly (and the chrome looks cleaner).
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        let bar = UINavigationBar.appearance()
        bar.standardAppearance.shadowColor = .clear
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance?.shadowColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(environment)
                .environmentObject(environment.instanceStore)
                .environmentObject(environment.settings)
                .environmentObject(environment.networkMonitor)
                .environmentObject(environment.notifications)
                .environmentObject(environment.updateChecker)
                .environmentObject(environment.appLock)
                .task {
                    await environment.notifications.refreshAuthorizationStatus()
                }
        }
        // Background polling (BGAppRefreshTask). No remote push is used.
        .backgroundTask(.appRefresh(BackgroundRefreshManager.refreshTaskIdentifier)) {
            await environment.backgroundRefresh.performRefresh()
            await environment.backgroundRefresh.scheduleNextRefresh()
        }
        #if targetEnvironment(macCatalyst)
        .commands {
            // Native Mac menu bar additions.
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Services") {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .nautilarrRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}

/// Root wrapper that applies the user's accent colour and light/dark preference
/// app-wide. It reads `settings` as an `@EnvironmentObject` (the environment
/// objects are attached to *this* view), so SwiftUI re-evaluates it the moment
/// either value changes — appearance updates live, without a relaunch.
private struct AppRootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updateChecker: UpdateChecker
    @EnvironmentObject private var appLock: AppLockManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var locked = false
    @State private var didInitialGate = false

    var body: some View {
        Group {
            if appLock.isLocked {
                // Master-password lock: RootView (and its data loads) only start
                // after the store is unlocked, so nothing reads secrets while locked.
                AppLockView()
            } else {
                mainContent
            }
        }
        .tint(settings.accent.color)
        .preferredColorScheme(settings.colorScheme.swiftUIScheme)
        .dynamicTypeSize(settings.textSize.dynamicTypeSize)
        // Soft tint for grouped list rows ("cards"), read by `.tintedCards()` on
        // every List/Form so the cards harmonise with the tinted background.
        .environment(\.cardTint, settings.background.cardColor)
        // Driving the locale through the environment re-resolves every `Text`
        // against the newly-selected localization *in place* — without rebuilding
        // the view tree. Crucially, this preserves navigation state (the user
        // stays on the Appearance screen they changed the language from) instead
        // of being kicked back to Home, which a `.id(settings.appLanguage)`
        // full-tree rebuild used to do.
        .environment(\.locale, Locale(identifier: settings.localeIdentifier))
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                appLock.softLock()
                if settings.faceIDOnLaunch { locked = true }
                // Queue the next background poll so health/import/request
                // notifications can fire while the app is closed. Without this
                // the OS never runs the refresh task at all.
                environment.backgroundRefresh.scheduleNextRefresh()
            } else if phase == .active && locked {
                Task { await unlock() }
            }
        }
    }

    private var mainContent: some View {
        RootView()
            // When Face ID-locked, blur the whole app; the frosted PrivacyLockView
            // on top hides everything so nothing sensitive shows until unlocked.
            .blur(radius: locked ? 26 : 0)
            .overlay {
                if locked {
                    PrivacyLockView(reason: "Unlock Nautilarr") { await unlock() }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: locked)
            .task { await updateChecker.checkOnLaunch() }
            .task { environment.backgroundRefresh.scheduleNextRefresh() }
            .alert("Update available", isPresented: Binding(
                get: { updateChecker.available != nil },
                set: { if !$0 { updateChecker.available = nil } }
            )) {
                Button("Download") {
                    if let update = updateChecker.available { openURL(update.url) }
                    updateChecker.available = nil
                }
                Button("Later", role: .cancel) { updateChecker.available = nil }
            } message: {
                if let update = updateChecker.available {
                    Text("Nautilarr \(update.version) is available (you have \(UpdateChecker.currentVersion)). Download it, then replace the app in Applications.")
                }
            }
            .task {
                guard !didInitialGate else { return }
                didInitialGate = true
                if settings.faceIDOnLaunch {
                    locked = true
                    await unlock()
                }
            }
    }

    private func unlock() async {
        if await BiometricGate.authenticate(reason: "Unlock Nautilarr") {
            locked = false
        }
    }
}

extension Notification.Name {
    /// Broadcast to ask the active screen to refresh (Cmd-R on Mac).
    static let nautilarrRefresh = Notification.Name("nautilarrRefresh")
}
