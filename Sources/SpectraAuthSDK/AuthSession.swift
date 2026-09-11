import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public let user: AppUser
    public let accessToken: AccessToken
    public let refreshToken: AppUserRefreshToken?
    public let isNewAppUser: Bool?
    public let idToken: String?
    public let userSummary: AppUserSummary?

    public init(
        user: AppUser,
        accessToken: AccessToken,
        refreshToken: AppUserRefreshToken? = nil,
        isNewAppUser: Bool? = nil,
        idToken: String? = nil,
        userSummary: AppUserSummary? = nil
    ) {
        self.user = user
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.isNewAppUser = isNewAppUser
        self.idToken = idToken
        self.userSummary = userSummary
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

public struct AppUserSummary: Codable, Equatable, Sendable {
    public let email: String?
    public let emailVerified: Bool?
    public let displayName: String?
    public let givenName: String?
    public let familyName: String?

    public init(
        email: String? = nil,
        emailVerified: Bool? = nil,
        displayName: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil
    ) {
        self.email = email
        self.emailVerified = emailVerified
        self.displayName = displayName
        self.givenName = givenName
        self.familyName = familyName
    }
}
