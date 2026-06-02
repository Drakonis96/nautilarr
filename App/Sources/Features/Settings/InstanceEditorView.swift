import SwiftUI
import NautilarrCore

/// Form for adding or editing a service instance, including a live connection
/// test. Works as a sheet on all platforms.
struct InstanceEditorView: View {
    @EnvironmentObject private var instanceStore: InstanceStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: InstanceEditorViewModel
    private let isEditing: Bool
    @State private var certResetConfirmed = false

    init(instance: ServiceInstance? = nil, credential: Credential = .none) {
        _model = StateObject(wrappedValue: InstanceEditorViewModel(instance: instance, credential: credential))
        isEditing = instance != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                connectionSection
                credentialSection
                headersSection
                advancedSection
                testSection
                if isEditing { deleteSection }
            }
            .navigationTitle(isEditing ? "Edit Service" : "Add Service")
            .alert("Certificate pin reset", isPresented: $certResetConfirmed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The pinned certificate was forgotten. It will be re-pinned on the next connection.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!model.isValid)
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                instanceStore.remove(model.makeInstance())
                dismiss()
            } label: {
                Label("Delete Service", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var detailsSection: some View {
        Section("Service") {
            // A NavigationLink + List selector is used instead of a Picker:
            // Picker rows ignore the icon's frame and render the vector logos at
            // their (wildly varying) intrinsic size. List rows honour the frame.
            NavigationLink {
                ServiceTypeSelectionList(selection: $model.type)
            } label: {
                HStack {
                    Text("Type")
                    Spacer()
                    ServiceIcon(type: model.type, size: 22)
                    Text(model.type.displayName).foregroundStyle(.secondary)
                }
            }
            TextField("Name", text: $model.name)
                .textContentTypeNone()
        }
    }

    private var connectionSection: some View {
        Section {
            TextField("Primary host (e.g. 192.168.1.10)", text: $model.primaryHost)
                .autocorrectionDisabled()
                .textInputAutocapitalizationNever()
            TextField("Fallback host (optional)", text: $model.fallbackHost)
                .autocorrectionDisabled()
                .textInputAutocapitalizationNever()
            TextField("Port (default \(model.type.defaultPort))", text: $model.portText)
                .keyboardTypeNumberPad()
            TextField("URL base (optional, e.g. /sonarr)", text: $model.urlBase)
                .autocorrectionDisabled()
                .textInputAutocapitalizationNever()
            Toggle("Use HTTPS", isOn: $model.useHTTPS)
            Toggle("Allow self-signed certificates", isOn: $model.allowSelfSigned)
            if isEditing && model.allowSelfSigned {
                Button("Reset pinned certificate") {
                    instanceStore.resetPinnedCertificates(for: model.makeInstance())
                    certResetConfirmed = true
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("You can also paste a full URL into the host field. A self-signed certificate is trusted only for this instance's hosts, and pinned on first connection — if it later changes, the connection is refused. Reset the pin after deliberately regenerating the certificate.")
        }
    }

    @ViewBuilder
    private var credentialSection: some View {
        Section("Credentials") {
            switch model.type.authenticationKind {
            case .apiKeyHeader, .apiKeyQuery:
                SecureField("API Key", text: $model.apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalizationNever()
            case .basicAuth, .cookieSession, .transmissionSession:
                TextField("Username", text: $model.username)
                    .textInputAutocapitalizationNever()
                SecureField("Password", text: $model.password)
            case .sshCredentials:
                TextField("Username", text: $model.username)
                    .textInputAutocapitalizationNever()
                SecureField("Password / passphrase (optional)", text: $model.password)
                TextField("Private key (optional)", text: $model.sshPrivateKey, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
    }

    private var headersSection: some View {
        Section {
            ForEach($model.headers) { $pair in
                HStack {
                    TextField("Header", text: $pair.key)
                        .textInputAutocapitalizationNever()
                    Divider()
                    TextField("Value", text: $pair.value)
                        .textInputAutocapitalizationNever()
                }
            }
            .onDelete { model.headers.remove(atOffsets: $0) }
            Button {
                model.headers.append(.init(key: "", value: ""))
            } label: {
                Label("Add header", systemImage: "plus")
            }
        } header: {
            Text("Custom HTTP headers")
        } footer: {
            Text("For reverse proxies such as Cloudflare Access (CF-Access-Client-Id / -Secret).")
        }
    }

    private var advancedSection: some View {
        Section("Connectivity") {
            Picker("Host selection", selection: $model.hostSelection) {
                Text("Automatic (LAN/WAN)").tag(ServiceInstance.HostSelection.automatic)
                Text("Always primary").tag(ServiceInstance.HostSelection.forcePrimary)
                Text("Always fallback").tag(ServiceInstance.HostSelection.forceFallback)
            }
            HStack {
                Text("Timeout (s)")
                Spacer()
                TextField("30", text: $model.timeoutText)
                    .keyboardTypeNumberPad()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await model.testConnection(monitor: networkMonitor) }
            } label: {
                HStack {
                    if model.isTesting { ProgressView().controlSize(.small) }
                    Text("Test Connection")
                }
            }
            .disabled(!model.isValid || model.isTesting)

            if let result = model.testResult {
                Label {
                    Text(result.message)
                } icon: {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                }
                .font(.subheadline)
            }
        }
    }

    private func save() {
        let instance = model.makeInstance()
        let credential = model.makeCredential()
        if isEditing {
            instanceStore.update(instance, credential: credential)
        } else {
            instanceStore.add(instance, credential: credential)
        }
        dismiss()
    }
}

/// Service-type picker rendered as a `List` (so logos honour their frame),
/// grouped by category, with a checkmark on the current selection.
private struct ServiceTypeSelectionList: View {
    @Binding var selection: ServiceType
    @Environment(\.dismiss) private var dismiss

    private var categories: [(name: String, types: [ServiceType])] {
        let order = ["Media Management", "Requests & Downloads", "Monitoring & Servers"]
        let grouped = Dictionary(grouping: ServiceType.allCases, by: \.category)
        return order.compactMap { name in
            guard let types = grouped[name] else { return nil }
            return (name, types)
        }
    }

    var body: some View {
        List {
            ForEach(categories, id: \.name) { category in
                Section(category.name) {
                    ForEach(category.types) { type in
                        Button {
                            selection = type
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ServiceIcon(type: type, size: 26)
                                Text(type.displayName).foregroundStyle(.primary)
                                Spacer()
                                if type == selection {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.teal)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Service Type")
    }
}

// MARK: - Cross-platform text field modifiers
// (Some `UITextInput`-style modifiers differ between iOS and Mac Catalyst; these
//  wrappers keep call-sites clean and compile everywhere.)

private extension View {
    func textInputAutocapitalizationNever() -> some View {
        #if os(iOS)
        return self.textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }
    func keyboardTypeNumberPad() -> some View {
        #if os(iOS)
        return self.keyboardType(.numberPad)
        #else
        return self
        #endif
    }
    func textContentTypeNone() -> some View { self }
}
