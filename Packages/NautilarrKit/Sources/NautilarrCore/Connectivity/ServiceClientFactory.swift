import Foundation

/// Assembles a network-aware `APIClient` for a `ServiceInstance`.
///
/// The produced client recomputes its candidate base URLs on every request,
/// consulting the `NetworkMonitor` so that the LAN host is tried first on
/// Wi-Fi/ethernet and the WAN/fallback host first otherwise — unless the
/// instance pins a specific host via `hostSelection`.
public enum ServiceClientFactory {
    public static func makeClient(
        for instance: ServiceInstance,
        credential: Credential,
        monitor: NetworkMonitor? = nil,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) -> APIClient {
        let authorizer = AuthorizerFactory.make(for: instance.type, credential: credential)
        let hosts = Set(instance.candidateBaseURLs(preferFallbackFirst: false).compactMap { $0.host })

        let provider: APIClient.BaseURLProvider = {
            let preferFallback = monitor?.snapshot().prefersFallbackFirst ?? false
            return instance.candidateBaseURLs(preferFallbackFirst: preferFallback)
        }

        return APIClient(
            baseURLProvider: provider,
            authorizer: authorizer,
            extraHeaders: instance.customHeaders,
            allowSelfSignedHosts: instance.allowSelfSignedCertificates ? hosts : [],
            timeout: instance.timeout,
            sessionConfiguration: sessionConfiguration
        )
    }
}
