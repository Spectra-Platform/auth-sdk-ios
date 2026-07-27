import Foundation

func appUserSessionEndpointURL(baseURL: URL, path: String) throws -> URL {
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

func setAppUserSessionJSONHeaders(on request: inout URLRequest) {
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
}

func decodeAppUserSessionResponse(
    _ data: Data,
    configuration: AuthClientConfiguration,
    expectedService: AuthService,
    expectedAppUserId: String? = nil
) throws -> AuthSession {
    let decoded = try decodeAppUserSessionResponseBody(data)
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

private func decodeAppUserSessionResponseBody(_ data: Data) throws -> AppUserSessionResponse {
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

struct AppUserSessionRefreshRequest: Encodable {
    let refreshToken: String
    let service: String
    let accessTtlSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case service
        case accessTtlSeconds = "access_ttl_seconds"
    }
}

struct AppUserSessionLogoutRequest: Encodable {
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
