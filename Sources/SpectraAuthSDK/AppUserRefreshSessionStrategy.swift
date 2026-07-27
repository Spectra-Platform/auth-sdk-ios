import Foundation

public struct AppUserRefreshSessionStrategy: ServiceScopedAuthTokenRefreshStrategy, ServiceAwareAuthTokenRefreshStrategy, AuthSessionRevocationStrategy {
    public let service: AuthService
    public let refreshTtlSeconds: Int?
    public let accessTtlSeconds: Int?
    public let additionalHeaders: [String: String]

    private let appUserIdProvider: @Sendable () async throws -> String
    private let transport: any AuthHTTPTransport
    private let clock: any AuthClock

    public init(
        service: AuthService,
        refreshTtlSeconds: Int? = nil,
        accessTtlSeconds: Int? = nil,
        additionalHeaders: [String: String] = [:],
        appUserIdProvider: @escaping @Sendable () async throws -> String,
        transport: any AuthHTTPTransport = URLSessionAuthHTTPTransport(),
        clock: any AuthClock = SystemAuthClock()
    ) {
        self.service = service
        self.refreshTtlSeconds = refreshTtlSeconds
        self.accessTtlSeconds = accessTtlSeconds
        self.additionalHeaders = additionalHeaders
        self.appUserIdProvider = appUserIdProvider
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
        return try await createSession(for: service, configuration: configuration)
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
            path: "/internal/dev/v1/app-user-sessions/logout"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(AppUserSessionLogoutRequest(
            refreshToken: refreshToken.value
        ))

        let (_, response) = try await transport.data(for: request)
        guard response.statusCode == 204 || response.statusCode == 401 || response.statusCode == 409 else {
            throw AuthError.tokenRefreshFailed(statusCode: response.statusCode)
        }
    }

    private func createSession(
        for service: AuthService,
        configuration: AuthClientConfiguration
    ) async throws -> AuthSession {
        let appUserId = try await appUserIdProvider()
        var request = URLRequest(url: try appUserSessionEndpointURL(
            baseURL: configuration.baseURL,
            path: "/internal/dev/v1/app-user-sessions"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(AppUserSessionCreateRequest(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            environment: configuration.environment.rawValue,
            service: service.rawValue,
            appUserId: appUserId,
            refreshTtlSeconds: refreshTtlSeconds,
            accessTtlSeconds: accessTtlSeconds
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 201 else {
            throw AuthError.tokenRefreshFailed(statusCode: response.statusCode)
        }
        return try decodeAppUserSessionResponse(
            data,
            configuration: configuration,
            expectedService: service,
            expectedAppUserId: appUserId
        )
    }

    private func refreshExistingSession(
        refreshToken: String,
        for service: AuthService,
        configuration: AuthClientConfiguration
    ) async throws -> AuthSession {
        var request = URLRequest(url: try appUserSessionEndpointURL(
            baseURL: configuration.baseURL,
            path: "/internal/dev/v1/app-user-sessions/refresh"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
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

private struct AppUserSessionCreateRequest: Encodable {
    let projectId: String
    let publicClientId: String
    let environment: String
    let service: String
    let appUserId: String
    let refreshTtlSeconds: Int?
    let accessTtlSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case environment
        case service
        case appUserId = "app_user_id"
        case refreshTtlSeconds = "refresh_ttl_seconds"
        case accessTtlSeconds = "access_ttl_seconds"
    }
}
