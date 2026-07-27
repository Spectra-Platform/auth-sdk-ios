import Foundation

public protocol AuthTokenRefreshStrategy: Sendable {
    func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession
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
