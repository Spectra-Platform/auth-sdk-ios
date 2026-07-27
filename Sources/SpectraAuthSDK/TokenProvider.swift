import Foundation

public protocol TokenProvider: Sendable {
    var currentUser: AppUser? { get async }

    func getAccessToken(forceRefresh: Bool) async throws -> AccessToken
    func refresh() async throws -> AccessToken
    func logout() async
}

public extension TokenProvider {
    func getAccessToken() async throws -> AccessToken {
        try await getAccessToken(forceRefresh: false)
    }

    func authorizationHeader(forceRefresh: Bool = false) async throws -> String {
        let token = try await getAccessToken(forceRefresh: forceRefresh)
        return "\(token.tokenType) \(token.value)"
    }

    func authorizedRequest(
        _ request: URLRequest,
        forceRefresh: Bool = false
    ) async throws -> URLRequest {
        var authorized = request
        authorized.setValue(
            try await authorizationHeader(forceRefresh: forceRefresh),
            forHTTPHeaderField: "Authorization"
        )
        return authorized
    }
}

public struct AccessToken: Codable, Equatable, Sendable {
    public let value: String
    public let tokenType: String
    public let expiresAt: Date
    public let scopes: Set<String>
    public let audience: Set<String>

    public init(
        value: String,
        tokenType: String = "Bearer",
        expiresAt: Date,
        scopes: Set<String> = [],
        audience: Set<String> = []
    ) {
        self.value = value
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.audience = audience
    }

    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt <= date.addingTimeInterval(leeway)
    }
}
