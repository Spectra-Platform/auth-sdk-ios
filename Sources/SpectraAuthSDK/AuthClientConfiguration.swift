import Foundation

public struct AuthClientConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let projectId: String
    public let publicClientId: String
    public let environment: AuthEnvironment
    public let redirectURI: URL?

    public init(
        baseURL: URL,
        projectId: String,
        publicClientId: String,
        environment: AuthEnvironment,
        redirectURI: URL? = nil
    ) {
        self.baseURL = baseURL
        self.projectId = projectId
        self.publicClientId = publicClientId
        self.environment = environment
        self.redirectURI = redirectURI
    }
}

public enum AuthEnvironment: String, Equatable, Sendable {
    case test
    case live
}
