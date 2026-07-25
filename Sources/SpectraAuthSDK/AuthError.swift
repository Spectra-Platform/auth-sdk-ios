import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case refreshUnavailable
    case unauthenticated
    case invalidTokenResponse
    case tokenRefreshFailed(statusCode: Int)
    case invalidConfiguration
    case invalidConfigurationReason(String)
    case sessionCacheUnavailable
    case sessionCacheFailed(operation: AuthSessionCacheOperation, reason: String)
}

public enum AuthSessionCacheOperation: String, Equatable, Sendable {
    case load
    case store
    case clear
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .refreshUnavailable:
            return "No auth refresh strategy is configured for this AuthClient."
        case .unauthenticated:
            return "No authenticated user session is available."
        case .invalidTokenResponse:
            return "The auth token response was missing required fields or did not match the requested project, environment, user, or audience."
        case let .tokenRefreshFailed(statusCode):
            return "Auth token refresh failed with HTTP status \(statusCode)."
        case .invalidConfiguration:
            return "Auth client configuration is invalid."
        case let .invalidConfigurationReason(reason):
            return reason
        case .sessionCacheUnavailable:
            return "No auth session cache is configured for this AuthClient."
        case let .sessionCacheFailed(operation, reason):
            return "Auth session cache \(operation.rawValue) failed: \(reason)"
        }
    }
}
