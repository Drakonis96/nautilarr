import Foundation
import LocalAuthentication

/// Thin wrapper over `LocalAuthentication` for Face ID / Touch ID gating.
/// Uses only on-device biometrics — no entitlement, no data leaves the device.
enum BiometricGate {
    /// Whether the device can evaluate biometrics (or device passcode fallback).
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Prompts for biometric (with passcode fallback) authentication.
    /// Returns `true` on success. If biometrics are unavailable, returns `true`
    /// so the gate never locks the user out of their own app.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
