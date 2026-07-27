import Foundation

public protocol AppUserSessionProvider: Sendable {
    func createSession(
        for service: AuthService,
        configuration: AuthClientConfiguration,
        transport: any AuthHTTPTransport
    ) async throws -> AuthSession
}

public struct DevMockAppUserSessionProvider: AppUserSessionProvider {
    private let providerSubjectProvider: @Sendable () async throws -> String

    public init(providerSubject: String) {
        self.providerSubjectProvider = { providerSubject }
    }

    public init(providerSubjectProvider: @escaping @Sendable () async throws -> String) {
        self.providerSubjectProvider = providerSubjectProvider
    }

    public func createSession(
        for service: AuthService,
        configuration: AuthClientConfiguration,
        transport: any AuthHTTPTransport
    ) async throws -> AuthSession {
        guard configuration.environment == .test else {
            throw AuthError.invalidConfigurationReason(
                "dev_mock app-user session provider is only available for non-production test environments."
            )
        }
        let providerSubject = try await providerSubjectProvider()
        guard Self.isSafeProviderSubject(providerSubject) else {
            throw AuthError.invalidConfigurationReason(
                "dev_mock provider subject must start with an alphanumeric character and contain only alphanumeric, dot, underscore, colon, at, or hyphen characters."
            )
        }

        var request = URLRequest(url: try appUserSessionEndpointURL(
            baseURL: configuration.baseURL,
            path: "/v1/app-user-sessions/dev-provider"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        request.httpBody = try JSONEncoder().encode(PublicDevProviderAppUserSessionCreateRequest(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            environment: configuration.environment.rawValue,
            providerSubject: providerSubject,
            service: service.rawValue
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 201 else {
            throw AuthError.tokenRefreshFailed(statusCode: response.statusCode)
        }
        return try decodeAppUserSessionResponse(
            data,
            configuration: configuration,
            expectedService: service
        )
    }

    private static func isSafeProviderSubject(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._:@-]{0,254}$"#,
            options: .regularExpression
        ) != nil
    }
}

public struct PublicAppUserSessionStrategy: ServiceScopedAuthTokenRefreshStrategy, ServiceAwareAuthTokenRefreshStrategy, AuthSessionRevocationStrategy {
    public let service: AuthService
    public let accessTtlSeconds: Int?

    private let sessionProvider: any AppUserSessionProvider
    private let transport: any AuthHTTPTransport
    private let clock: any AuthClock

    public init(
        service: AuthService,
        sessionProvider: any AppUserSessionProvider,
        accessTtlSeconds: Int? = nil,
        transport: any AuthHTTPTransport = URLSessionAuthHTTPTransport(),
        clock: any AuthClock = SystemAuthClock()
    ) {
        self.service = service
        self.sessionProvider = sessionProvider
        self.accessTtlSeconds = accessTtlSeconds
        self.transport = transport
        self.clock = clock
    }

    public func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        try await refreshToken(for: service, configuration: configuration, currentSession: currentSession)
    }

    public func refreshToken(
        for service: AuthService,
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        if let refreshToken = currentSession?.refreshToken,
           !refreshToken.isExpired(at: clock.now) {
            return try await refreshExistingSession(
                refreshToken: refreshToken.value,
                for: service,
                configuration: configuration
            )
        }
        return try await sessionProvider.createSession(
            for: service,
            configuration: configuration,
            transport: transport
        )
    }

    public func revokeSession(
        configuration: AuthClientConfiguration,
        session: AuthSession
    ) async throws {
        guard let refreshToken = session.refreshToken else {
            return
        }
        var request = URLRequest(url: try appUserSessionEndpointURL(
            baseURL: configuration.baseURL,
            path: "/v1/app-user-sessions/logout"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        request.httpBody = try JSONEncoder().encode(AppUserSessionLogoutRequest(
            refreshToken: refreshToken.value
        ))

        let (_, response) = try await transport.data(for: request)
        guard response.statusCode == 204 || response.statusCode == 401 || response.statusCode == 409 else {
            throw AuthError.tokenRefreshFailed(statusCode: response.statusCode)
        }
    }

    private func refreshExistingSession(
        refreshToken: String,
        for service: AuthService,
        configuration: AuthClientConfiguration
    ) async throws -> AuthSession {
        var request = URLRequest(url: try appUserSessionEndpointURL(
            baseURL: configuration.baseURL,
            path: "/v1/app-user-sessions/refresh"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        request.httpBody = try JSONEncoder().encode(AppUserSessionRefreshRequest(
            refreshToken: refreshToken,
            service: service.rawValue,
            accessTtlSeconds: accessTtlSeconds
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 201 else {
            throw AuthError.tokenRefreshFailed(statusCode: response.statusCode)
        }
        return try decodeAppUserSessionResponse(
            data,
            configuration: configuration,
            expectedService: service
        )
    }
}

private struct PublicDevProviderAppUserSessionCreateRequest: Encodable {
    let projectId: String
    let publicClientId: String
    let environment: String
    let provider = "dev_mock"
    let providerSubject: String
    let service: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case environment
        case provider
        case providerSubject = "provider_subject"
        case service
    }
}
