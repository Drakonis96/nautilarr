import SwiftUI
import NautilarrCore

/// Editable draft of a `ServiceInstance` plus its credential, used by the
/// add/edit form. Keeps secret fields separate so they only touch the Keychain
/// on save.
@MainActor
final class InstanceEditorViewModel: ObservableObject {
    @Published var type: ServiceType
    @Published var name: String
    @Published var primaryHost: String
    @Published var fallbackHost: String
    @Published var portText: String
    @Published var urlBase: String
    @Published var useHTTPS: Bool
    @Published var allowSelfSigned: Bool
    @Published var hostSelection: ServiceInstance.HostSelection
    @Published var timeoutText: String
    @Published var headers: [HeaderPair]

    // Credential fields
    @Published var apiKey: String
    @Published var username: String
    @Published var password: String
    @Published var sshPrivateKey: String

    @Published var isTesting = false
    @Published var testResult: ConnectionTester.Result?

    let existingID: UUID?

    struct HeaderPair: Identifiable, Hashable {
        let id = UUID()
        var key: String
        var value: String
    }

    init(instance: ServiceInstance? = nil, credential: Credential = .none) {
        self.existingID = instance?.id
        self.type = instance?.type ?? .sonarr
        self.name = instance?.name ?? ""
        self.primaryHost = instance?.primaryHost ?? ""
        self.fallbackHost = instance?.fallbackHost ?? ""
        self.portText = instance?.port.map(String.init) ?? ""
        self.urlBase = instance?.urlBase ?? ""
        self.useHTTPS = instance?.useHTTPS ?? false
        self.allowSelfSigned = instance?.allowSelfSignedCertificates ?? false
        self.hostSelection = instance?.hostSelection ?? .automatic
        self.timeoutText = instance.map { String(Int($0.timeout)) } ?? "30"
        self.headers = (instance?.customHeaders ?? [:]).map { HeaderPair(key: $0.key, value: $0.value) }

        switch credential {
        case let .apiKey(key):
            apiKey = key; username = ""; password = ""; sshPrivateKey = ""
        case let .usernamePassword(user, pass):
            apiKey = ""; username = user; password = pass; sshPrivateKey = ""
        case let .ssh(user, pass, key):
            apiKey = ""; username = user; password = pass ?? ""; sshPrivateKey = key ?? ""
        case .none:
            apiKey = ""; username = ""; password = ""; sshPrivateKey = ""
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !primaryHost.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The credential as currently entered, shaped by the service's auth kind.
    func makeCredential() -> Credential {
        switch type.authenticationKind {
        case .apiKeyHeader, .apiKeyQuery:
            return .apiKey(apiKey.trimmingCharacters(in: .whitespaces))
        case .basicAuth, .cookieSession, .transmissionSession:
            return .usernamePassword(username: username, password: password)
        case .sshCredentials:
            return .ssh(username: username, password: password.isEmpty ? nil : password,
                        privateKey: sshPrivateKey.isEmpty ? nil : sshPrivateKey)
        }
    }

    func makeInstance() -> ServiceInstance {
        var headerDict: [String: String] = [:]
        for pair in headers where !pair.key.trimmingCharacters(in: .whitespaces).isEmpty {
            headerDict[pair.key] = pair.value
        }
        return ServiceInstance(
            id: existingID ?? UUID(),
            type: type,
            name: name.trimmingCharacters(in: .whitespaces),
            primaryHost: primaryHost.trimmingCharacters(in: .whitespaces),
            fallbackHost: fallbackHost.isEmpty ? nil : fallbackHost.trimmingCharacters(in: .whitespaces),
            port: Int(portText),
            urlBase: urlBase.isEmpty ? nil : urlBase,
            useHTTPS: useHTTPS,
            allowSelfSignedCertificates: allowSelfSigned,
            customHeaders: headerDict,
            hostSelection: hostSelection,
            timeout: TimeInterval(timeoutText) ?? 30
        )
    }

    func testConnection(monitor: NetworkMonitor) async {
        isTesting = true
        testResult = nil
        let result = await ConnectionTester.test(
            instance: makeInstance(),
            credential: makeCredential(),
            monitor: monitor
        )
        testResult = result
        isTesting = false
    }
}
