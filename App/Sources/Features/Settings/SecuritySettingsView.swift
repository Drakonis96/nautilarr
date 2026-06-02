import SwiftUI

/// Biometric (Face ID / Touch ID) gates + the master-password App Lock. All
/// on-device via LocalAuthentication; no biometric data is stored or transmitted.
struct SecuritySettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var instanceStore: InstanceStore

    @State private var showSet = false
    @State private var showDisable = false
    @State private var showChange = false
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var currentPassword = ""
    @State private var errorMessage: String?

    /// App Lock (file-store encryption) only applies when secrets use the file
    /// fallback. On Keychain builds the system already gates secrets.
    private var appLockApplies: Bool { !instanceStore.secretsUseKeychain }

    var body: some View {
        Form {
            appLockSection
                .tintedCards()
            Section {
                Toggle("Face ID for SSH", isOn: Binding(
                    get: { settings.faceIDForSSH }, set: { settings.faceIDForSSH = $0 }
                ))
                Toggle("Face ID for Settings", isOn: Binding(
                    get: { settings.faceIDForSettings }, set: { settings.faceIDForSettings = $0 }
                ))
                Toggle("Face ID on Launch", isOn: Binding(
                    get: { settings.faceIDOnLaunch }, set: { settings.faceIDOnLaunch = $0 }
                ))
            } header: {
                Text("Biometrics")
            } footer: {
                Text(BiometricGate.isAvailable
                     ? "Biometrics stay on device. Nautilarr never stores your biometric data."
                     : "No biometrics are enrolled on this device; these gates will be skipped.")
            }
            .tintedCards()
        }
        .navigationTitle("Security")
        .alert("Set master password", isPresented: $showSet) {
            SecureField("New password", text: $newPassword)
            SecureField("Confirm password", text: $confirmPassword)
            Button("Set") { setMasterPassword() }
            Button("Cancel", role: .cancel) { clearFields() }
        } message: {
            Text("This password encrypts your saved API keys and credentials. There is NO recovery — if you forget it you must reset and re-enter your services.")
        }
        .alert("Turn off App Lock", isPresented: $showDisable) {
            SecureField("Master password", text: $currentPassword)
            Button("Turn off", role: .destructive) { disableLock() }
            Button("Cancel", role: .cancel) { clearFields() }
        } message: {
            Text("Enter your master password to remove App Lock.")
        }
        .alert("Change master password", isPresented: $showChange) {
            SecureField("Current password", text: $currentPassword)
            SecureField("New password", text: $newPassword)
            Button("Change") { changeMasterPassword() }
            Button("Cancel", role: .cancel) { clearFields() }
        }
        .alert("App Lock", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var appLockSection: some View {
        Section {
            Toggle("App Lock (master password)", isOn: Binding(
                get: { appLock.isEnabled },
                set: { wantsOn in if wantsOn { showSet = true } else { showDisable = true } }
            ))
            .disabled(!appLockApplies)
            if appLock.isEnabled {
                Button("Change master password") { showChange = true }
            }
        } header: {
            Text("App Lock")
        } footer: {
            if appLockApplies {
                Text("When on, your saved API keys and credentials are encrypted with a master password. You'll unlock the app at launch with the password, Face ID or Touch ID. Without it, the on-disk data can't be decrypted — even if the file is stolen.")
            } else {
                Text("Your secrets are stored in the system Keychain, already protected by your device passcode and biometrics, so an extra master password isn't needed here.")
            }
        }
    }

    // MARK: Actions

    private func setMasterPassword() {
        defer { clearFields() }
        guard newPassword.count >= 4 else { errorMessage = "Use at least 4 characters."; return }
        guard newPassword == confirmPassword else { errorMessage = "Passwords don't match."; return }
        if !appLock.enable(password: newPassword) { errorMessage = "Couldn't enable App Lock." }
    }

    private func disableLock() {
        defer { clearFields() }
        if !appLock.disable(currentPassword: currentPassword) { errorMessage = "Wrong password." }
    }

    private func changeMasterPassword() {
        defer { clearFields() }
        guard newPassword.count >= 4 else { errorMessage = "Use at least 4 characters."; return }
        if !appLock.changePassword(old: currentPassword, new: newPassword) { errorMessage = "Wrong current password." }
    }

    private func clearFields() {
        newPassword = ""; confirmPassword = ""; currentPassword = ""
    }
}
