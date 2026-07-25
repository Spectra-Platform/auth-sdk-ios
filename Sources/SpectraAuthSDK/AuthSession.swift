import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public let user: AppUser
    public let accessToken: AccessToken

    public init(user: AppUser, accessToken: AccessToken) {
        self.user = user
        self.accessToken = accessToken
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
