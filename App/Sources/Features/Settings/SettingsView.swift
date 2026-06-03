import SwiftUI
import UniformTypeIdentifiers
import NautilarrCore

/// Onboarding + settings hub: manage service instances, appearance,
/// notifications and configuration import/export.
struct SettingsView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var settings: AppSettings

    @State private var editingInstance: ServiceInstance?
    @State private var isAddingInstance = false
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument: ConfigDocument?
    @State private var importError: String?
    @State private var unlocked = false
    @State private var showAbout = false
    @State private var exportPassphrase = ""
    @State private var showExportPassphrase = false
    @State private var importPassphrase = ""
    @State private var pendingImportData: Data?
    @State private var showImportPassphrase = false

    var body: some View {
        Group {
            if settings.faceIDForSettings && !unlocked {
                BiometricLockView(reason: "Unlock Settings") {
                    unlocked = await BiometricGate.authenticate(reason: "Unlock Settings")
                }
            } else {
                settingsList
            }
        }
        .task {
            if settings.faceIDForSettings && !unlocked {
                unlocked = await BiometricGate.authenticate(reason: "Unlock Settings")
            }
        }
    }

    private var settingsList: some View {
        List {
            brandHeader
            servicesSection.tintedCards()
            appearanceSection.tintedCards()
            configurationSection.tintedCards()
            aboutSection.tintedCards()
        }
        .sheet(isPresented: $isAddingInstance) {
            InstanceEditorView()
        }
        .sheet(item: $editingInstance) { instance in
            InstanceEditorView(instance: instance,
                               credential: instanceStore.credential(for: instance),
                               proxyCredential: instanceStore.proxyCredential(for: instance))
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .data,
            defaultFilename: "nautilarr-backup"
        ) { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showExportPassphrase) {
            PassphrasePromptView(
                title: "Encrypt backup",
                message: "Choose a password to encrypt this backup. It contains your API keys and passwords, so you'll need this password to import it.",
                confirmLabel: "Export",
                passphrase: $exportPassphrase
            ) {
                let pass = exportPassphrase; exportPassphrase = ""
                showExportPassphrase = false
                guard !pass.isEmpty, let data = instanceStore.exportConfiguration(passphrase: pass) else { return }
                exportDocument = ConfigDocument(data: data)
                isExporting = true
            } onCancel: {
                exportPassphrase = ""; showExportPassphrase = false
            }
        }
        .sheet(isPresented: $showImportPassphrase) {
            PassphrasePromptView(
                title: "Backup password",
                message: "Enter the password used when this backup was created.",
                confirmLabel: "Import",
                passphrase: $importPassphrase
            ) {
                let pass = importPassphrase; importPassphrase = ""
                showImportPassphrase = false
                if let data = pendingImportData {
                    do { try instanceStore.importConfiguration(data, passphrase: pass) }
                    catch { importError = error.localizedDescription }
                }
                pendingImportData = nil
            } onCancel: {
                importPassphrase = ""; pendingImportData = nil; showImportPassphrase = false
            }
        }
        .alert("Import failed", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showAbout) { AboutSplashView() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAddingInstance = true } label: {
                    Label("Add Service", systemImage: "plus")
                }
            }
        }
    }

    private var brandHeader: some View {
        Section {
            Button {
                showAbout = true
            } label: {
                VStack(spacing: 8) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 116)
                        .shadow(color: Theme.teal.opacity(0.45), radius: 12, y: 5)
                    Text("nautilARR").font(.title.weight(.heavy))
                    Text("v\(appVersion)").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
        }
    }

    private var servicesSection: some View {
        let services = instanceStore.instancesInActiveNetwork
        return Section {
            NavigationLink {
                NetworksSettingsView().appBackground(settings.background)
            } label: {
                Label {
                    HStack {
                        Text("Networks")
                        Spacer()
                        Text(instanceStore.activeNetwork?.name ?? "").foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "globe")
                }
            }
            if services.isEmpty {
                Button { isAddingInstance = true } label: {
                    Label("Add your first service", systemImage: "plus.circle")
                }
            }
            ForEach(services) { instance in
                Button { editingInstance = instance } label: {
                    InstanceRow(instance: instance)
                        .contentShape(Rectangle())   // whole row is tappable, not just the name
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                offsets.map { services[$0] }.forEach(instanceStore.remove)
            }
        } header: {
            Text("Services")
        } footer: {
            Text("Services belong to the active network. Secrets are stored in the system Keychain, never in plain text.")
        }
    }

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceView().appBackground(settings.background)
            } label: {
                Label("Appearance", systemImage: "paintpalette")
            }
            NavigationLink {
                NotificationSettingsView().appBackground(settings.background)
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
            NavigationLink {
                DownloadsSettingsView().appBackground(settings.background)
            } label: {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            NavigationLink {
                ShortcutsSettingsView().appBackground(settings.background)
            } label: {
                Label("Plex / Jellyfin shortcuts", systemImage: "play.rectangle.on.rectangle")
            }
            NavigationLink {
                SecuritySettingsView().appBackground(settings.background)
            } label: {
                Label("Security", systemImage: "lock.shield")
            }
            NavigationLink {
                AdvancedSettingsView().appBackground(settings.background)
            } label: {
                Label("Advanced", systemImage: "gearshape.2")
            }
        }
    }

    private var configurationSection: some View {
        Section("Configuration") {
            Button {
                showExportPassphrase = true
            } label: {
                Label("Export configuration…", systemImage: "square.and.arrow.up")
            }
            Button {
                isImporting = true
            } label: {
                Label("Import configuration…", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("License", value: "MIT")
            Text("Nautilarr — an open-source client for self-hosted media services.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                do {
                    try instanceStore.importConfiguration(data, passphrase: nil)
                } catch InstanceStore.ConfigImportError.passphraseRequired {
                    // Encrypted backup — ask for its password, then retry.
                    pendingImportData = data
                    showImportPassphrase = true
                }
            } catch {
                importError = error.localizedDescription
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}

private struct InstanceRow: View {
    let instance: ServiceInstance

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(type: instance.type, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name).font(.body)
                Text("\(instance.type.displayName) · \(instance.primaryHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A minimal `FileDocument` wrapping JSON config data for `fileExporter`.
struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
