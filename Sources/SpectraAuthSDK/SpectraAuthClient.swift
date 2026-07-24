import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SpectraAuthClientError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case emptyAccessToken
    case sessionUnavailable
    case refreshNotImplemented
}

public struct SpectraAuthClient: SpectraAccessTokenProviding, Sendable {
    private let configuration: SpectraAuthConfiguration
    private let tokenProvider: (any SpectraAccessTokenProviding)?
    private let sessionStore: any SpectraAuthSessionStoring
    private let transport: any SpectraAuthTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: SpectraAuthConfiguration,
        tokenProvider: (any SpectraAccessTokenProviding)? = nil,
        sessionStore: any SpectraAuthSessionStoring = InMemorySpectraAuthSessionStore(),
        transport: any SpectraAuthTransport = URLSessionSpectraAuthTransport()
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.sessionStore = sessionStore
        self.transport = transport
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func currentUser() async throws -> SpectraAuthUser? {
        try await sessionStore.loadSession()?.accessToken.user
    }

    public func accessToken() async throws -> String {
        try await getAccessToken(forceRefresh: false).token
    }

    public func getAccessToken(forceRefresh: Bool = false) async throws -> SpectraAuthAccessToken {
        if let tokenProvider {
            let token = try await tokenProvider.accessToken()
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SpectraAuthClientError.emptyAccessToken
            }
            return SpectraAuthAccessToken(
                token: token,
                expiresAt: .distantFuture,
                user: SpectraAuthUser(
                    appUserId: "external-token-provider",
                    projectId: configuration.projectId,
                    environment: configuration.environment
                )
            )
        }

        guard let session = try await sessionStore.loadSession() else {
            throw SpectraAuthClientError.sessionUnavailable
        }
        guard forceRefresh || session.accessToken.isExpired() else {
            return session.accessToken
        }
        throw SpectraAuthClientError.refreshNotImplemented
    }

    public func setSession(_ session: SpectraAuthSession) async throws {
        guard !session.accessToken.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpectraAuthClientError.emptyAccessToken
        }
        try await sessionStore.saveSession(session)
    }

    public func logout() async throws {
        try await sessionStore.clearSession()
    }

    public func makePlatformRequest(
        method: String,
        path: String,
        idempotencyKey: String? = nil
    ) async throws -> URLRequest {
        let accessToken = try await accessToken()
        let normalizedBase = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(normalizedBase)/platform/v1/projects/\(configuration.projectId)/\(path)") else {
            throw SpectraAuthClientError.invalidBaseURL
        }
        components.percentEncodedPath = components.percentEncodedPath
            .replacingOccurrences(of: configuration.projectId, with: percentEncode(configuration.projectId))
        guard let url = components.url else {
            throw SpectraAuthClientError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" && method != "DELETE" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.setValue(configuration.publicClientId, forHTTPHeaderField: "X-Spectra-Public-Client-Id")
        request.setValue(configuration.environment.rawValue, forHTTPHeaderField: "X-Spectra-Environment")
        return request
    }

    public func send<T: Decodable>(
        _ request: URLRequest,
        expecting type: T.Type,
        expectedStatusCodes: Set<Int>
    ) async throws -> T {
        let response = try await transport.send(request)
        guard expectedStatusCodes.contains(response.statusCode) else {
            throw SpectraAuthClientError.unexpectedStatusCode(response.statusCode)
        }
        return try decoder.decode(T.self, from: response.data)
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

