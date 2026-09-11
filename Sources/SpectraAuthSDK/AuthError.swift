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
    case requestFailed(
        code: String,
        status: Int?,
        requestId: String?,
        message: String,
        retryAfterSeconds: Int?
    )
}

public enum AuthSessionCacheOperation: String, Equatable, Sendable {
    case load
    case store
    case clear
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        message
    }

    public var code: String {
        switch self {
        case .refreshUnavailable:
            return "REFRESH_UNAVAILABLE"
        case .unauthenticated:
            return "SESSION_UNAVAILABLE"
        case .invalidTokenResponse:
            return "RESPONSE_INVALID"
        case let .tokenRefreshFailed(statusCode):
            return "HTTP_\(statusCode)"
        case .invalidConfiguration:
            return "CONFIGURATION_INVALID"
        case .invalidConfigurationReason:
            return "CONFIGURATION_INVALID"
        case .sessionCacheUnavailable:
            return "SESSION_CACHE_UNAVAILABLE"
        case .sessionCacheFailed:
            return "SESSION_CACHE_FAILED"
        case let .requestFailed(code, _, _, _, _):
            return code
        }
    }

    public var status: Int? {
        switch self {
        case let .tokenRefreshFailed(statusCode):
            return statusCode
        case let .requestFailed(_, status, _, _, _):
            return status
        default:
            return nil
        }
    }

    public var requestId: String? {
        switch self {
        case let .requestFailed(_, _, requestId, _, _):
            return requestId
        default:
            return nil
        }
    }

    public var retryAfterSeconds: Int? {
        switch self {
        case let .requestFailed(_, _, _, _, retryAfterSeconds):
            return retryAfterSeconds
        default:
            return nil
        }
    }

    public var message: String {
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
        case let .requestFailed(_, _, _, message, _):
            return message
        }
    }
}
