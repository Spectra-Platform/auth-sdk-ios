import Foundation

public struct SpectraAuthUser: Sendable, Codable, Equatable {
    public let appUserId: String
    public let projectId: String
    public let environment: SpectraAuthEnvironment

    public init(
        appUserId: String,
        projectId: String,
        environment: SpectraAuthEnvironment
    ) {
        self.appUserId = appUserId
        self.projectId = projectId
        self.environment = environment
    }
}

public struct SpectraAuthAccessToken: Sendable, Codable, Equatable {
    public let token: String
    public let tokenType: String
    public let expiresAt: Date
    public let user: SpectraAuthUser

    public init(
        token: String,
        tokenType: String = "Bearer",
        expiresAt: Date,
        user: SpectraAuthUser
    ) {
        self.token = token
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.user = user
    }

    public func isExpired(now: Date = Date(), leeway: TimeInterval = 30) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

public struct SpectraAuthSession: Sendable, Codable, Equatable {
    public let accessToken: SpectraAuthAccessToken

    public init(accessToken: SpectraAuthAccessToken) {
        self.accessToken = accessToken
    }
}

