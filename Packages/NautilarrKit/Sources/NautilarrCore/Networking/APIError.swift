import Foundation

/// A normalised error surfaced by `APIClient`, regardless of the underlying
/// service. The UI maps these to friendly, actionable messages.
public enum APIError: Error, Equatable, Sendable {
    /// The instance configuration did not yield a usable URL.
    case invalidBaseURL
    /// The response was not an HTTP response or could not be interpreted.
    case invalidResponse
    /// 401 — credentials missing or wrong.
    case unauthorized
    /// 403 — authenticated but not permitted (or blocked by a proxy).
    case forbidden
    /// 404 — endpoint/resource not found (often a wrong urlBase).
    case notFound
    /// Any other non-success status code, with an optional response snippet.
    case server(statusCode: Int, body: String?)
    /// The response body could not be decoded into the expected type.
    case decoding(String)
    /// A transport-level failure (DNS, TLS, connection refused, …).
    case transport(String)
    /// Every candidate host failed; carries each host's error description.
    case allHostsFailed([String])
    /// The request exceeded the configured timeout.
    case timedOut
    /// The task was cancelled.
    case cancelled
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The server address is not valid. Check the host, port and path."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .unauthorized:
            return "Authentication failed. Check the API key or credentials."
        case .forbidden:
            return "Access was denied. Check permissions or proxy headers."
        case .notFound:
            return "The requested resource was not found. Check the URL base."
        case let .server(statusCode, body):
            if let body, !body.isEmpty {
                return "Server error \(statusCode): \(body)"
            }
            return "Server error \(statusCode)."
        case let .decoding(detail):
            return "Could not read the server response. \(detail)"
        case let .transport(detail):
            return "Could not reach the server. \(detail)"
        case let .allHostsFailed(reasons):
            return "All configured hosts failed:\n" + reasons.joined(separator: "\n")
        case .timedOut:
            return "The request timed out."
        case .cancelled:
            return "The request was cancelled."
        }
    }
}

extension APIError {
    /// Maps a low-level error into an `APIError`, preserving cancellation and
    /// timeout semantics.
    static func from(_ error: Error) -> APIError {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timedOut
            case .cancelled: return .cancelled
            default: return .transport(urlError.localizedDescription)
            }
        }
        if let apiError = error as? APIError { return apiError }
        return .transport(error.localizedDescription)
    }
}
