import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case refreshUnavailable
    case unauthenticated
    case invalidTokenResponse
}
