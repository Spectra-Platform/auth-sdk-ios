import Foundation

public protocol AuthHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAuthHTTPTransport: AuthHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidTokenResponse
        }
        return (data, http)
    }
}

public struct AppUserAccessTokenRefreshStrategy: AuthTokenRefreshStrategy {
    public let service: AuthService
    public let ttlSeconds: Int?
    public let additionalHeaders: [String: String]

    private let appUserIdProvider: @Sendable () async throws -> String
    private let transport: any AuthHTTPTransport

    public init(
        service: AuthService,
        ttlSeconds: Int? = nil,
        additionalHeaders: [String: String] = [:],
        appUserIdProvider: @escaping @Sendable () async throws -> String,
        transport: any AuthHTTPTransport = URLSessionAuthHTTPTransport()
    ) {
        self.service = service
        self.ttlSeconds = ttlSeconds
        self.additionalHeaders = additionalHeaders
        self.appUserIdProvider = appUserIdProvider
        self.transport = transport
    }

    public func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        let appUserId = try await appUserIdProvider()
        var request = URLRequest(url: try endpointURL(baseURL: configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(AppUserAccessTokenIssueRequest(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            environment: configuration.environment.rawValue,
            service: service.rawValue,
            appUserId: appUserId,
            ttlSeconds: ttlSeconds
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 201 else {
            throw AuthError.tokenRefreshFailed(statusCode: response.statusCode)
        }
        let decoded = try decodeResponse(data)
        guard decoded.data.projectId == configuration.projectId,
              decoded.data.environment == configuration.environment.rawValue,
              decoded.data.appUserId == appUserId,
              decoded.data.audiences == [service.rawValue],
              decoded.data.scopes.isEmpty == false else {
            throw AuthError.invalidTokenResponse
        }
        return AuthSession(
            user: AppUser(id: decoded.data.appUserId, projectId: decoded.data.projectId),
            accessToken: AccessToken(
                value: decoded.data.accessToken,
                tokenType: decoded.data.tokenType,
                expiresAt: decoded.data.expiresAt,
                scopes: Set(decoded.data.scopes),
                audience: Set(decoded.data.audiences)
            )
        )
    }
}

private func endpointURL(baseURL: URL) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          components.scheme != nil,
          components.host != nil else {
        throw AuthError.invalidConfiguration
    }
    components.path = "/internal/dev/v1/app-user-access-tokens"
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
        throw AuthError.invalidConfiguration
    }
    return url
}

private func decodeResponse(_ data: Data) throws -> AppUserAccessTokenIssueResponse {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = fractionalDateFormatter.date(from: value) ?? wholeSecondDateFormatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected RFC3339 date")
    }
    do {
        return try decoder.decode(AppUserAccessTokenIssueResponse.self, from: data)
    } catch {
        throw AuthError.invalidTokenResponse
    }
}

private let fractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let wholeSecondDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private struct AppUserAccessTokenIssueRequest: Encodable {
    let projectId: String
    let publicClientId: String
    let environment: String
    let service: String
    let appUserId: String
    let ttlSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case environment
        case service
        case appUserId = "app_user_id"
        case ttlSeconds = "ttl_seconds"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(publicClientId, forKey: .publicClientId)
        try container.encode(environment, forKey: .environment)
        try container.encode(service, forKey: .service)
        try container.encode(appUserId, forKey: .appUserId)
        try container.encodeIfPresent(ttlSeconds, forKey: .ttlSeconds)
    }
}

private struct AppUserAccessTokenIssueResponse: Decodable {
    let data: Body

    struct Body: Decodable {
        let accessToken: String
        let tokenType: String
        let expiresAt: Date
        let projectId: String
        let environment: String
        let appUserId: String
        let scopes: [String]
        let audiences: [String]

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresAt = "expires_at"
            case projectId = "project_id"
            case environment
            case appUserId = "app_user_id"
            case scopes
            case audiences
        }
    }
}
