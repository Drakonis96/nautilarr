import Foundation
import Combine
import NautilarrCore

/// Coordinates the optional **master password** (App Lock). When enabled, the
/// local secret-store key is wrapped with the password, so credentials can't be
/// read until the user unlocks — with the master password (cold launch) or
/// biometrics / device passcode (re-entry while the key is still in memory).
@MainActor
final class AppLockManager: ObservableObject {
    /// Whether the UI is currently locked.
    @Published var isLocked: Bool
    /// Whether a master password is configured (observable for Settings).
    @Published private(set) var isEnabled: Bool
    /// Last unlock error (e.g. wrong password), for the lock screen.
    @Published var lastError: String?

    init() {
        let enabled = FileSecretStore.isAppLockEnabled
        isEnabled = enabled
        // Locked at launch if a master password is configured.
        isLocked = enabled
    }

    /// Whether the store key is already in memory (so biometrics can re-gate
    /// without re-deriving from the password).
    var keyInMemory: Bool { FileSecretStore.isUnlocked }

    /// Whether biometrics / device passcode are available on this device.
    var biometricsAvailable: Bool { BiometricGate.isAvailable }

    func unlock(password: String) -> Bool {
        if FileSecretStore.unlock(password: password) {
            isLocked = false; lastError = nil; return true
        }
        lastError = "Wrong password."
        return false
    }

    /// Biometric / passcode unlock. Only succeeds when the key is already in
    /// memory (returning from background); a cold launch needs the password.
    func unlockWithBiometrics() async -> Bool {
        guard FileSecretStore.isUnlocked else { return false }
        let ok = await BiometricGate.authenticate(reason: "Unlock Nautilarr")
        if ok { isLocked = false; lastError = nil }
        return ok
    }

    /// Soft-lock for backgrounding: hide the UI but keep the key in memory so
    /// returning only needs a quick biometric check.
    func softLock() { if isEnabled { isLocked = true } }

    // MARK: Configuration

    @discardableResult
    func enable(password: String) -> Bool {
        let ok = FileSecretStore.enableAppLock(password: password)
        if ok { isEnabled = true }
        return ok
    }

    @discardableResult
    func disable(currentPassword: String) -> Bool {
        let ok = FileSecretStore.disableAppLock(password: currentPassword)
        if ok { isEnabled = false; isLocked = false }
        return ok
    }

    @discardableResult
    func changePassword(old: String, new: String) -> Bool {
        FileSecretStore.changePassword(old: old, new: new)
    }
}
