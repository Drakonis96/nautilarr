import SwiftUI

/// Full-screen lock shown at launch (and after backgrounding) when a master
/// password is set. Unlock with the master password, or — when returning from
/// background with the key still in memory — Face ID / Touch ID / device passcode.
struct AppLockView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @State private var password = ""

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(color: Theme.teal.opacity(0.5), radius: 10, y: 4)
                Text("nautilARR").font(.title.weight(.heavy)).foregroundStyle(.white)
                Label("Locked", systemImage: "lock.fill")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))

                SecureField("Master password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .submitLabel(.go)
                    .onSubmit(submit)

                if let error = appLock.lastError {
                    Text(error).font(.caption).foregroundStyle(.yellow)
                }

                Button("Unlock", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Theme.navy)
                    .disabled(password.isEmpty)

                if appLock.biometricsAvailable && appLock.keyInMemory {
                    Button { Task { await appLock.unlockWithBiometrics() } } label: {
                        Label("Use Face ID / Touch ID", systemImage: "faceid")
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .task {
            // Returning from background with the key still in memory → offer
            // biometrics straight away.
            if appLock.biometricsAvailable && appLock.keyInMemory {
                _ = await appLock.unlockWithBiometrics()
            }
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        _ = appLock.unlock(password: password)
        password = ""
    }
}
