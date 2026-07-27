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

    public static func live(
        projectId: String,
        publicClientId: String,
        baseURL: URL = URL(string: "https://auth.spectra.kr")!,
        redirectURI: URL? = nil
    ) -> AuthClientConfiguration {
        AuthClientConfiguration(
            baseURL: baseURL,
            projectId: projectId,
            publicClientId: publicClientId,
            environment: .live,
            redirectURI: redirectURI
        )
    }

    public static func local(
        projectId: String,
        publicClientId: String,
        baseURL: URL = URL(string: "http://127.0.0.1:8081")!,
        redirectURI: URL? = nil
    ) -> AuthClientConfiguration {
        AuthClientConfiguration(
            baseURL: baseURL,
            projectId: projectId,
            publicClientId: publicClientId,
            environment: .test,
            redirectURI: redirectURI
        )
    }

    public static func custom(
        baseURL: URL,
        projectId: String,
        publicClientId: String,
        environment: AuthEnvironment,
        redirectURI: URL? = nil
    ) -> AuthClientConfiguration {
        AuthClientConfiguration(
            baseURL: baseURL,
            projectId: projectId,
            publicClientId: publicClientId,
            environment: environment,
            redirectURI: redirectURI
        )
    }

    public func validated() throws -> AuthClientConfiguration {
        guard baseURL.scheme?.isEmpty == false,
              baseURL.host?.isEmpty == false,
              projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              publicClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AuthError.invalidConfigurationReason(
                "AuthClientConfiguration requires a valid baseURL, projectId, and publicClientId."
            )
        }
        return self
    }
}

public enum AuthEnvironment: String, Equatable, Sendable {
    case test
    case live
}

public enum AuthService: String, Equatable, Sendable, Codable {
    case storage
    case email
    case notification
    case chat
    case call
}
