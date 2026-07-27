import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public let user: AppUser
    public let accessToken: AccessToken
    public let refreshToken: AppUserRefreshToken?

    public init(
        user: AppUser,
        accessToken: AccessToken,
        refreshToken: AppUserRefreshToken? = nil
    ) {
        self.user = user
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct AppUserRefreshToken: Codable, Equatable, Sendable {
    public let value: String
    public let expiresAt: Date
    public let sessionId: String

    public init(
        value: String,
        expiresAt: Date,
        sessionId: String
    ) {
        self.value = value
        self.expiresAt = expiresAt
        self.sessionId = sessionId
    }

    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt <= date.addingTimeInterval(leeway)
    }
}

public struct AppUser: Codable, Equatable, Sendable {
    public let id: String
    public let projectId: String

    public init(id: String, projectId: String) {
        self.id = id
        self.projectId = projectId
    }
}
