import Foundation

public protocol AuthTokenRefreshStrategy: Sendable {
    func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession
}

public protocol ServiceScopedAuthTokenRefreshStrategy: AuthTokenRefreshStrategy {
    var service: AuthService { get }
}

public protocol ServiceAwareAuthTokenRefreshStrategy: AuthTokenRefreshStrategy {
    func refreshToken(
        for service: AuthService,
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession
}

public protocol AuthSessionRevocationStrategy: Sendable {
    func revokeSession(
        configuration: AuthClientConfiguration,
        session: AuthSession
    ) async throws
}

public protocol AuthClock: Sendable {
    var now: Date { get }
}

public struct SystemAuthClock: AuthClock {
    public init() {}

    public var now: Date {
        Date()
    }
}
