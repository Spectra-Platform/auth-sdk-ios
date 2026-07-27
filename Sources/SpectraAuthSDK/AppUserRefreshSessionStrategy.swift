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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        return try decodeSessionResponse(
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        return try decodeSessionResponse(
            data,
            configuration: configuration,
            expectedService: service
        )
    }
}

private func appUserSessionEndpointURL(baseURL: URL, path: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          components.scheme != nil,
          components.host != nil else {
        throw AuthError.invalidConfigurationReason("Auth baseURL must include a scheme and host.")
    }
    components.path = path
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
        throw AuthError.invalidConfigurationReason("Auth session endpoint URL could not be built from baseURL.")
    }
    return url
}

private func decodeSessionResponse(
    _ data: Data,
    configuration: AuthClientConfiguration,
    expectedService: AuthService,
    expectedAppUserId: String? = nil
) throws -> AuthSession {
    let decoded = try decodeAppUserSessionResponse(data)
    guard decoded.data.projectId == configuration.projectId,
          decoded.data.publicClientId == configuration.publicClientId,
          decoded.data.environment == configuration.environment.rawValue,
          decoded.data.audiences == [expectedService.rawValue],
          decoded.data.scopes.isEmpty == false else {
        throw AuthError.invalidTokenResponse
    }
    if let expectedAppUserId, decoded.data.appUserId != expectedAppUserId {
        throw AuthError.invalidTokenResponse
    }
    return AuthSession(
        user: AppUser(id: decoded.data.appUserId, projectId: decoded.data.projectId),
        accessToken: AccessToken(
            value: decoded.data.accessToken,
            tokenType: decoded.data.tokenType,
            expiresAt: decoded.data.accessExpiresAt,
            scopes: Set(decoded.data.scopes),
            audience: Set(decoded.data.audiences)
        ),
        refreshToken: AppUserRefreshToken(
            value: decoded.data.refreshToken,
            expiresAt: decoded.data.refreshExpiresAt,
            sessionId: decoded.data.sessionId
        )
    )
}

private func decodeAppUserSessionResponse(_ data: Data) throws -> AppUserSessionResponse {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = appUserSessionFractionalDateFormatter.date(from: value)
            ?? appUserSessionWholeSecondDateFormatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected RFC3339 date")
    }
    do {
        return try decoder.decode(AppUserSessionResponse.self, from: data)
    } catch {
        throw AuthError.invalidTokenResponse
    }
}

private let appUserSessionFractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let appUserSessionWholeSecondDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

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

private struct AppUserSessionRefreshRequest: Encodable {
    let refreshToken: String
    let service: String
    let accessTtlSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case service
        case accessTtlSeconds = "access_ttl_seconds"
    }
}

private struct AppUserSessionLogoutRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct AppUserSessionResponse: Decodable {
    let data: Body

    struct Body: Decodable {
        let refreshToken: String
        let accessToken: String
        let tokenType: String
        let refreshExpiresAt: Date
        let accessExpiresAt: Date
        let projectId: String
        let environment: String
        let publicClientId: String
        let appUserId: String
        let sessionId: String
        let scopes: [String]
        let audiences: [String]

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
            case accessToken = "access_token"
            case tokenType = "token_type"
            case refreshExpiresAt = "refresh_expires_at"
            case accessExpiresAt = "access_expires_at"
            case projectId = "project_id"
            case environment
            case publicClientId = "public_client_id"
            case appUserId = "app_user_id"
            case sessionId = "session_id"
            case scopes
            case audiences
        }
    }
}
