import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case refreshUnavailable
    case unauthenticated
    case invalidTokenResponse
    case tokenRefreshFailed(statusCode: Int)
    case invalidConfiguration
}
