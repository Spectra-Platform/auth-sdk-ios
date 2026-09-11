import CryptoKit
import Foundation

#if canImport(Security)
import Security
#endif

#if canImport(AuthenticationServices)
@preconcurrency import AuthenticationServices
#endif

public typealias SpectraAuthClient = AuthClient

public enum SpectraAuthProvider: String, Codable, Equatable, Sendable {
    case google
    case apple
}

public enum SpectraAuthSignInPrompt: String, Codable, Equatable, Sendable {
    case selectAccount = "select_account"
}

public struct SpectraAuthSignInOptions: Sendable {
    public let redirectURI: URL?
    public let prompt: SpectraAuthSignInPrompt?
    public let timeout: Duration?
    public let prefersEphemeralWebBrowserSession: Bool
    public let webAuthenticationSessionProvider: (any SpectraWebAuthenticationSessionProvider)?

    public init(
        redirectURI: URL? = nil,
        prompt: SpectraAuthSignInPrompt? = nil,
        timeout: Duration? = nil,
        prefersEphemeralWebBrowserSession: Bool = false,
        webAuthenticationSessionProvider: (any SpectraWebAuthenticationSessionProvider)? = nil
    ) {
        self.redirectURI = redirectURI
        self.prompt = prompt
        self.timeout = timeout
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.webAuthenticationSessionProvider = webAuthenticationSessionProvider
    }
}

public struct SpectraGetAccessTokenOptions: Sendable {
    public let forceRefresh: Bool
    public let service: AuthService?

    public init(forceRefresh: Bool = false, service: AuthService? = nil) {
        self.forceRefresh = forceRefresh
        self.service = service
    }
}

public struct HostedAuthSessionStrategy: ServiceScopedAuthTokenRefreshStrategy, ServiceAwareAuthTokenRefreshStrategy, AuthSessionRevocationStrategy {
    public let service: AuthService = .auth
    public let tokenRefreshSkewSeconds: TimeInterval

    private let transport: any AuthHTTPTransport
    private let clock: any AuthClock

    public init(
        transport: any AuthHTTPTransport = URLSessionAuthHTTPTransport(),
        clock: any AuthClock = SystemAuthClock(),
        tokenRefreshSkewSeconds: TimeInterval = 60
    ) {
        self.transport = transport
        self.clock = clock
        self.tokenRefreshSkewSeconds = tokenRefreshSkewSeconds
    }

    public func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        try await refreshAuthSession(configuration: configuration, currentSession: currentSession)
    }

    public func refreshToken(
        for service: AuthService,
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        if service == .auth {
            return try await refreshAuthSession(
                configuration: configuration,
                currentSession: currentSession
            )
        }
        let authSession: AuthSession
        if let currentSession,
           currentSession.accessToken.isValid(
               for: .auth,
               at: clock.now,
               leeway: tokenRefreshSkewSeconds,
               allowMissingAudience: true
           ) {
            authSession = currentSession
        } else {
            authSession = try await refreshAuthSession(
                configuration: configuration,
                currentSession: currentSession
            )
        }
        return try await issueServiceAccessToken(
            service: service,
            configuration: configuration,
            authSession: authSession
        )
    }

    public func revokeSession(
        configuration: AuthClientConfiguration,
        session: AuthSession
    ) async throws {
        var request = URLRequest(url: try authEndpointURL(
            baseURL: configuration.baseURL,
            path: "/platform/v1/auth/sessions/current"
        ))
        request.httpMethod = "DELETE"
        setAppUserSessionJSONHeaders(on: &request)
        request.setValue(
            "\(session.accessToken.tokenType) \(session.accessToken.value)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(AuthSessionRevokeRequest(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            refreshToken: session.refreshToken?.value
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 204 else {
            throw try authRequestFailed(data: data, response: response)
        }
    }

    func createChallenge(
        provider: SpectraAuthProvider,
        redirectURI: URL,
        pkceChallenge: String,
        configuration: AuthClientConfiguration,
        timeout: Duration?
    ) async throws -> SpectraAuthChallenge {
        var request = URLRequest(url: try authEndpointURL(
            baseURL: configuration.baseURL,
            path: "/platform/v1/auth/social/challenges"
        ))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout?.timeInterval ?? 300
        setAppUserSessionJSONHeaders(on: &request)
        request.httpBody = try JSONEncoder().encode(SocialLoginChallengeRequest(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            provider: provider.rawValue,
            redirectURI: redirectURI.absoluteString,
            pkceChallenge: pkceChallenge,
            pkceChallengeMethod: "S256"
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 201 else {
            throw try authRequestFailed(data: data, response: response)
        }
        return try decodeEnvelope(data, as: SpectraAuthChallenge.self)
    }

    func exchangeAuthorizationCode(
        _ authorizationCode: String,
        pending: SpectraAuthPendingSignIn,
        configuration: AuthClientConfiguration,
        timeout: Duration?
    ) async throws -> AuthSession {
        var request = URLRequest(url: try authEndpointURL(
            baseURL: configuration.baseURL,
            path: "/platform/v1/auth/social/exchanges"
        ))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout?.timeInterval ?? 300
        setAppUserSessionJSONHeaders(on: &request)
        request.httpBody = try JSONEncoder().encode(SocialLoginExchangeRequest(
            challengeId: pending.challengeId,
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            provider: pending.provider.rawValue,
            redirectURI: pending.redirectURI.absoluteString,
            pkceVerifier: pending.pkceVerifier,
            credential: .init(authorizationCode: authorizationCode)
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw try authRequestFailed(data: data, response: response)
        }
        return try decodeAuthSession(data, configuration: configuration, now: clock.now)
    }

    private func refreshAuthSession(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        guard let refreshToken = currentSession?.refreshToken,
              !refreshToken.isExpired(at: clock.now) else {
            throw AuthError.unauthenticated
        }
        var request = URLRequest(url: try authEndpointURL(
            baseURL: configuration.baseURL,
            path: "/platform/v1/auth/sessions/refresh"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        request.httpBody = try JSONEncoder().encode(AuthSessionRefreshRequest(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            refreshToken: refreshToken.value
        ))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            throw try authRequestFailed(data: data, response: response)
        }
        let refreshed = try decodeAuthSession(data, configuration: configuration, now: clock.now)
        return AuthSession(
            user: refreshed.user,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            isNewAppUser: refreshed.isNewAppUser,
            idToken: refreshed.idToken ?? currentSession?.idToken,
            userSummary: refreshed.userSummary ?? currentSession?.userSummary
        )
    }

    private func issueServiceAccessToken(
        service: AuthService,
        configuration: AuthClientConfiguration,
        authSession: AuthSession
    ) async throws -> AuthSession {
        var request = URLRequest(url: try authEndpointURL(
            baseURL: configuration.baseURL,
            path: "/platform/v1/auth/sessions/current/access-tokens"
        ))
        request.httpMethod = "POST"
        setAppUserSessionJSONHeaders(on: &request)
        request.setValue(
            "\(authSession.accessToken.tokenType) \(authSession.accessToken.value)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(ServiceTokenRequest(service: service.rawValue))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 201 else {
            throw try authRequestFailed(data: data, response: response)
        }
        let token = try decodeServiceToken(data, service: service, configuration: configuration)
        return AuthSession(
            user: authSession.user,
            accessToken: token,
            refreshToken: authSession.refreshToken,
            isNewAppUser: authSession.isNewAppUser,
            idToken: authSession.idToken,
            userSummary: authSession.userSummary
        )
    }
}

public protocol SpectraWebAuthenticationSessionProvider: Sendable {
    func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String?,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL
}

public struct ASWebAuthenticationSessionProvider: SpectraWebAuthenticationSessionProvider {
    #if canImport(AuthenticationServices)
    private let presentationContextProviderBox: ASWebAuthenticationPresentationContextProviderBox

    public init(
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding? = nil
    ) {
        self.presentationContextProviderBox = ASWebAuthenticationPresentationContextProviderBox(
            value: presentationContextProvider
        )
    }
    #else
    public init() {}
    #endif

    public func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String?,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL {
        #if canImport(AuthenticationServices)
        let box = ASWebAuthenticationSessionBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: callbackURLScheme
                ) { callbackURL, error in
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                        return
                    }
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.requestFailed(
                            code: "SIGN_IN_CANCELLED",
                            status: nil,
                            requestId: nil,
                            message: "Spectra Auth sign-in was cancelled.",
                            retryAfterSeconds: nil
                        ))
                        return
                    }
                    continuation.resume(throwing: AuthError.requestFailed(
                        code: "SIGN_IN_FAILED",
                        status: nil,
                        requestId: nil,
                        message: "Spectra Auth sign-in failed.",
                        retryAfterSeconds: nil
                    ))
                }
                session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                session.presentationContextProvider = presentationContextProviderBox.value
                box.session = session
                if !session.start() {
                    continuation.resume(throwing: AuthError.requestFailed(
                        code: "WEB_AUTHENTICATION_SESSION_FAILED",
                        status: nil,
                        requestId: nil,
                        message: "ASWebAuthenticationSession could not be started.",
                        retryAfterSeconds: nil
                    ))
                }
            }
        } onCancel: {
            box.cancel()
        }
        #else
        throw AuthError.requestFailed(
            code: "WEB_AUTHENTICATION_SESSION_UNAVAILABLE",
            status: nil,
            requestId: nil,
            message: "ASWebAuthenticationSession is unavailable on this platform.",
            retryAfterSeconds: nil
        )
        #endif
    }
}

extension AuthClient {
    public init(
        configuration: AuthClientConfiguration,
        sessionStore: (any AuthSessionCache)?,
        transport: any AuthHTTPTransport = URLSessionAuthHTTPTransport(),
        clock: any AuthClock = SystemAuthClock()
    ) {
        self.init(
            configuration: configuration,
            refreshStrategy: HostedAuthSessionStrategy(
                transport: transport,
                clock: clock
            ),
            sessionCache: sessionStore,
            clock: clock,
            defaultService: .auth
        )
    }

    public static func restoringHostedSession(
        configuration: AuthClientConfiguration,
        sessionStore: any AuthSessionCache,
        transport: any AuthHTTPTransport = URLSessionAuthHTTPTransport(),
        clock: any AuthClock = SystemAuthClock()
    ) async throws -> AuthClient {
        try await AuthClient.restoringCachedSession(
            configuration: configuration,
            refreshStrategy: HostedAuthSessionStrategy(
                transport: transport,
                clock: clock
            ),
            sessionCache: sessionStore,
            clock: clock,
            defaultService: .auth
        )
    }

    public func preflightSignIn(
        _ provider: SpectraAuthProvider,
        options: SpectraAuthSignInOptions = SpectraAuthSignInOptions()
    ) throws {
        try beginHostedSignIn()
        endHostedSignIn()
        _ = try validatedHostedSignInInput(provider: provider, options: options)
    }

    @discardableResult
    public func signInWithGoogle(
        options: SpectraAuthSignInOptions = SpectraAuthSignInOptions()
    ) async throws -> AuthSession {
        try await signIn(.google, options: options)
    }

    @discardableResult
    public func signInWithApple(
        options: SpectraAuthSignInOptions = SpectraAuthSignInOptions()
    ) async throws -> AuthSession {
        try await signIn(.apple, options: options)
    }

    @discardableResult
    public func signIn(
        _ provider: SpectraAuthProvider,
        options: SpectraAuthSignInOptions = SpectraAuthSignInOptions()
    ) async throws -> AuthSession {
        try beginHostedSignIn()
        do {
            let input = try validatedHostedSignInInput(provider: provider, options: options)
            let strategy = hostedSessionStrategy()
            let pkce = try SpectraPKCEPair()
            let challenge = try await strategy.createChallenge(
                provider: provider,
                redirectURI: input.redirectURI,
                pkceChallenge: pkce.challenge,
                configuration: configuration,
                timeout: options.timeout
            )
            let pending = SpectraAuthPendingSignIn(
                provider: provider,
                redirectURI: input.redirectURI,
                challengeId: challenge.challengeId,
                state: challenge.state,
                nonce: challenge.nonce,
                pkceVerifier: pkce.verifier
            )
            setPendingHostedSignIn(pending)
            let callbackURL = try await withTimeout(options.timeout) {
                try await input.webAuthenticationSessionProvider.authenticate(
                    authorizationURL: try hostedAuthorizationURL(
                        provider: provider,
                        challenge: challenge,
                        pkceChallenge: pkce.challenge,
                        redirectURI: input.redirectURI,
                        prompt: options.prompt,
                        configuration: self.configuration
                    ),
                    callbackURLScheme: input.redirectURI.scheme,
                    prefersEphemeralWebBrowserSession: options.prefersEphemeralWebBrowserSession
                )
            }
            let session = try await completeHostedCallback(
                callbackURL,
                timeout: options.timeout
            )
            endHostedSignIn()
            return session
        } catch {
            clearPendingHostedSignIn()
            endHostedSignIn()
            throw error
        }
    }

    @discardableResult
    public func handleCallback(url: URL) async throws -> Bool {
        _ = try await completeHostedCallback(url, timeout: nil)
        endHostedSignIn()
        return true
    }

    public func getAccessToken(
        _ options: SpectraGetAccessTokenOptions
    ) async throws -> AccessToken {
        if let service = options.service,
           service != .auth {
            return try await getAccessToken(for: service, forceRefresh: options.forceRefresh)
        }
        return try await getAccessToken(forceRefresh: options.forceRefresh)
    }

    private func completeHostedCallback(
        _ callbackURL: URL,
        timeout: Duration?
    ) async throws -> AuthSession {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.requestFailed(
                code: "REDIRECT_URI_INVALID",
                status: nil,
                requestId: nil,
                message: "Spectra Auth callback URL is invalid.",
                retryAfterSeconds: nil
            )
        }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        let state = query["state"] ?? ""
        if let error = query["error"] {
            throw AuthError.requestFailed(
                code: error == "access_denied" ? "SIGN_IN_CANCELLED" : "SIGN_IN_FAILED",
                status: nil,
                requestId: nil,
                message: error == "access_denied" ? "Spectra Auth sign-in was cancelled." : "Spectra Auth sign-in failed.",
                retryAfterSeconds: nil
            )
        }
        guard let code = query["code"],
              code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AuthError.requestFailed(
                code: "AUTHORIZATION_CODE_MISSING",
                status: nil,
                requestId: nil,
                message: "Spectra Auth callback did not include an authorization code.",
                retryAfterSeconds: nil
            )
        }
        let pending = try consumePendingHostedSignIn(
            matchingState: state,
            redirectURI: callbackURL.spectraCallbackBaseURL()
        )
        let session = try await hostedSessionStrategy().exchangeAuthorizationCode(
            code,
            pending: pending,
            configuration: configuration,
            timeout: timeout
        )
        try await storeHostedAuthSession(session)
        return session
    }

    private func validatedHostedSignInInput(
        provider: SpectraAuthProvider,
        options: SpectraAuthSignInOptions
    ) throws -> HostedSignInInput {
        _ = provider
        _ = try configuration.validated()
        let redirectURI = options.redirectURI ?? configuration.redirectURI
        guard let redirectURI else {
            throw AuthError.requestFailed(
                code: "REDIRECT_URI_REQUIRED",
                status: nil,
                requestId: nil,
                message: "A callback redirectURI is required for hosted sign-in.",
                retryAfterSeconds: nil
            )
        }
        try validateHostedRedirectURI(redirectURI)
        return HostedSignInInput(
            redirectURI: redirectURI,
            webAuthenticationSessionProvider: options.webAuthenticationSessionProvider ?? ASWebAuthenticationSessionProvider()
        )
    }
}

struct SpectraAuthPendingSignIn: Equatable, Sendable {
    let provider: SpectraAuthProvider
    let redirectURI: URL
    let challengeId: String
    let state: String
    let nonce: String
    let pkceVerifier: String
}

private struct HostedSignInInput: Sendable {
    let redirectURI: URL
    let webAuthenticationSessionProvider: any SpectraWebAuthenticationSessionProvider
}

private struct SpectraPKCEPair {
    let verifier: String
    let challenge: String

    init() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AuthError.requestFailed(
                code: "CRYPTO_UNAVAILABLE",
                status: nil,
                requestId: nil,
                message: "Secure random generation is unavailable.",
                retryAfterSeconds: nil
            )
        }
        verifier = Data(bytes).spectraBase64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).spectraBase64URLEncodedString()
    }
}

struct SpectraAuthChallenge: Decodable {
    let challengeId: String
    let state: String
    let nonce: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case state
        case nonce
        case expiresAt = "expires_at"
    }
}

private struct SocialLoginChallengeRequest: Encodable {
    let projectId: String
    let publicClientId: String
    let provider: String
    let redirectURI: String
    let pkceChallenge: String
    let pkceChallengeMethod: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case provider
        case redirectURI = "redirect_uri"
        case pkceChallenge = "pkce_challenge"
        case pkceChallengeMethod = "pkce_challenge_method"
    }
}

private struct SocialLoginExchangeRequest: Encodable {
    let challengeId: String
    let projectId: String
    let publicClientId: String
    let provider: String
    let redirectURI: String
    let pkceVerifier: String
    let credential: AuthorizationCodeCredential

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case provider
        case redirectURI = "redirect_uri"
        case pkceVerifier = "pkce_verifier"
        case credential
    }
}

private struct AuthorizationCodeCredential: Encodable {
    let kind = "authorization_code"
    let authorizationCode: String

    enum CodingKeys: String, CodingKey {
        case kind
        case authorizationCode = "authorization_code"
    }
}

private struct AuthSessionRefreshRequest: Encodable {
    let projectId: String
    let publicClientId: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case refreshToken = "refresh_token"
    }
}

private struct AuthSessionRevokeRequest: Encodable {
    let projectId: String
    let publicClientId: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicClientId = "public_client_id"
        case refreshToken = "refresh_token"
    }
}

private struct ServiceTokenRequest: Encodable {
    let service: String
}

private struct AuthEnvelope<Body: Decodable>: Decodable {
    let data: Body
}

private struct AuthSessionResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let appUserId: String
    let projectId: String
    let isNewAppUser: Bool
    let idToken: String?
    let user: AppUserSummaryResponse?
    let expiresIn: TimeInterval?
    let refreshExpiresIn: TimeInterval?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case appUserId = "app_user_id"
        case projectId = "project_id"
        case isNewAppUser = "is_new_app_user"
        case idToken = "id_token"
        case user
        case expiresIn = "expires_in"
        case refreshExpiresIn = "refresh_expires_in"
        case tokenType = "token_type"
    }
}

private struct AppUserSummaryResponse: Decodable {
    let email: String?
    let emailVerified: Bool?
    let displayName: String?
    let givenName: String?
    let familyName: String?

    enum CodingKeys: String, CodingKey {
        case email
        case emailVerified = "email_verified"
        case displayName = "display_name"
        case givenName = "given_name"
        case familyName = "family_name"
    }
}

private struct ServiceTokenResponse: Decodable {
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

private struct AuthErrorEnvelope: Decodable {
    let error: Body

    struct Body: Decodable {
        let code: String
        let message: String?
        let requestId: String?
        let retryAfterSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case requestId = "request_id"
            case retryAfterSeconds = "retry_after_seconds"
        }
    }
}

private func decodeAuthSession(
    _ data: Data,
    configuration: AuthClientConfiguration,
    now: Date
) throws -> AuthSession {
    let response = try decodeEnvelope(data, as: AuthSessionResponse.self)
    guard response.projectId == configuration.projectId else {
        throw AuthError.invalidTokenResponse
    }
    let accessExpiresAt = response.expiresIn.map { now.addingTimeInterval($0) }
        ?? jwtExpiresAt(response.accessToken)
        ?? now
    let refreshExpiresAt = now.addingTimeInterval(response.refreshExpiresIn ?? 2_592_000)
    return AuthSession(
        user: AppUser(id: response.appUserId, projectId: response.projectId),
        accessToken: AccessToken(
            value: response.accessToken,
            tokenType: response.tokenType ?? "Bearer",
            expiresAt: accessExpiresAt,
            scopes: [],
            audience: []
        ),
        refreshToken: AppUserRefreshToken(
            value: response.refreshToken,
            expiresAt: refreshExpiresAt,
            sessionId: response.appUserId
        ),
        isNewAppUser: response.isNewAppUser,
        idToken: safeOIDCIDToken(response.idToken),
        userSummary: response.user?.summary
    )
}

private func decodeServiceToken(
    _ data: Data,
    service: AuthService,
    configuration: AuthClientConfiguration
) throws -> AccessToken {
    let response = try decodeEnvelope(data, as: ServiceTokenResponse.self)
    guard response.projectId == configuration.projectId,
          response.environment == configuration.environment.rawValue,
          response.audiences == [service.rawValue],
          response.scopes.isEmpty == false else {
        throw AuthError.invalidTokenResponse
    }
    return AccessToken(
        value: response.accessToken,
        tokenType: response.tokenType,
        expiresAt: response.expiresAt,
        scopes: Set(response.scopes),
        audience: Set(response.audiences)
    )
}

private func decodeEnvelope<Body: Decodable>(
    _ data: Data,
    as bodyType: Body.Type
) throws -> Body {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = hostedFractionalDateFormatter.date(from: value)
            ?? hostedWholeSecondDateFormatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected RFC3339 date.")
    }
    do {
        return try decoder.decode(AuthEnvelope<Body>.self, from: data).data
    } catch {
        throw AuthError.invalidTokenResponse
    }
}

private func authRequestFailed(data: Data, response: HTTPURLResponse) throws -> AuthError {
    if let decoded = try? JSONDecoder().decode(AuthErrorEnvelope.self, from: data) {
        return AuthError.requestFailed(
            code: decoded.error.code,
            status: response.statusCode,
            requestId: decoded.error.requestId ?? response.value(forHTTPHeaderField: "X-Request-ID"),
            message: decoded.error.message ?? "Spectra Auth request failed.",
            retryAfterSeconds: decoded.error.retryAfterSeconds ?? retryAfterSeconds(from: response)
        )
    }
    return AuthError.requestFailed(
        code: "RESPONSE_INVALID",
        status: response.statusCode,
        requestId: response.value(forHTTPHeaderField: "X-Request-ID"),
        message: "Spectra Auth returned an invalid error response.",
        retryAfterSeconds: retryAfterSeconds(from: response)
    )
}

private func hostedAuthorizationURL(
    provider: SpectraAuthProvider,
    challenge: SpectraAuthChallenge,
    pkceChallenge: String,
    redirectURI: URL,
    prompt: SpectraAuthSignInPrompt?,
    configuration: AuthClientConfiguration
) throws -> URL {
    let realmPath = "/realms/platform-\(configuration.environment.rawValue)/protocol/openid-connect/auth"
    guard var components = URLComponents(url: try authEndpointURL(
        baseURL: configuration.baseURL,
        path: realmPath
    ), resolvingAgainstBaseURL: false) else {
        throw AuthError.invalidConfiguration
    }
    components.queryItems = [
        URLQueryItem(name: "client_id", value: configuration.publicClientId),
        URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "scope", value: "openid email profile"),
        URLQueryItem(name: "state", value: challenge.state),
        URLQueryItem(name: "nonce", value: challenge.nonce),
        URLQueryItem(name: "code_challenge", value: pkceChallenge),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
        URLQueryItem(name: "kc_idp_hint", value: providerAlias(
            projectId: configuration.projectId,
            publicClientId: configuration.publicClientId,
            environment: configuration.environment,
            provider: provider
        )),
    ]
    if let prompt {
        components.queryItems?.append(URLQueryItem(name: "prompt", value: prompt.rawValue))
    }
    guard let url = components.url else {
        throw AuthError.invalidConfiguration
    }
    return url
}

private func providerAlias(
    projectId: String,
    publicClientId: String,
    environment: AuthEnvironment,
    provider: SpectraAuthProvider
) -> String {
    let raw = [
        projectId,
        environment.rawValue,
        publicClientId,
        provider.rawValue,
    ].joined(separator: "\u{0}")
    let digest = SHA256.hash(data: Data(raw.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "spectra-\(environment.rawValue)-\(provider.rawValue)-\(hex.prefix(24))"
}

private func validateHostedRedirectURI(_ redirectURI: URL) throws {
    guard let scheme = redirectURI.scheme,
          scheme.isEmpty == false,
          redirectURI.fragment == nil,
          redirectURI.query == nil,
          redirectURI.absoluteString.range(of: #"[\s\u{0000}-\u{001f}\u{007f}*]"#, options: .regularExpression) == nil else {
        throw AuthError.requestFailed(
            code: "REDIRECT_URI_INVALID",
            status: nil,
            requestId: nil,
            message: "Use an exact callback URI without query, fragment, whitespace or wildcards.",
            retryAfterSeconds: nil
        )
    }
    if scheme == "http" || scheme == "https" {
        guard redirectURI.host?.isEmpty == false else {
            throw AuthError.requestFailed(
                code: "REDIRECT_URI_INVALID",
                status: nil,
                requestId: nil,
                message: "HTTP(S) callback URI must include a host.",
                retryAfterSeconds: nil
            )
        }
    }
}

func authEndpointURL(baseURL: URL, path: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          components.scheme != nil,
          components.host != nil else {
        throw AuthError.invalidConfigurationReason("Auth baseURL must include a scheme and host.")
    }
    components.path = path
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
        throw AuthError.invalidConfigurationReason("Auth endpoint URL could not be built from baseURL.")
    }
    return url
}

private func withTimeout<T: Sendable>(
    _ timeout: Duration?,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    guard let timeout else {
        return try await operation()
    }
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw AuthError.requestFailed(
                code: "SIGN_IN_TIMEOUT",
                status: nil,
                requestId: nil,
                message: "Spectra Auth sign-in timed out.",
                retryAfterSeconds: nil
            )
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After"),
          value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        return nil
    }
    if let seconds = Int(value) {
        return seconds
    }
    if let date = HTTPDateFormatter.date(from: value) {
        return max(0, Int(ceil(date.timeIntervalSinceNow)))
    }
    return nil
}

private func safeOIDCIDToken(_ value: String?) -> String? {
    guard let value,
          value.count <= 8192,
          value.range(of: #"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
        return nil
    }
    return value
}

private func jwtExpiresAt(_ token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2,
          let payload = Data(spectraBase64URLEncoded: String(parts[1])),
          let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let exp = json["exp"] as? TimeInterval else {
        return nil
    }
    return Date(timeIntervalSince1970: exp)
}

private extension AppUserSummaryResponse {
    var summary: AppUserSummary? {
        let summary = AppUserSummary(
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            emailVerified: emailVerified,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            givenName: givenName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            familyName: familyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        if summary.email == nil,
           summary.emailVerified == nil,
           summary.displayName == nil,
           summary.givenName == nil,
           summary.familyName == nil {
            return nil
        }
        return summary
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

extension URL {
    func spectraCallbackBaseURL() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? self
    }

    func spectraCallbackMatches(_ other: URL) -> Bool {
        spectraCallbackBaseURL().absoluteString == other.spectraCallbackBaseURL().absoluteString
    }
}

private extension Data {
    init?(spectraBase64URLEncoded value: String) {
        let normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: padded)
    }

    func spectraBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum HTTPDateFormatter {
    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}

private let hostedFractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let hostedWholeSecondDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

#if canImport(AuthenticationServices)
private final class ASWebAuthenticationPresentationContextProviderBox: @unchecked Sendable {
    let value: ASWebAuthenticationPresentationContextProviding?

    init(value: ASWebAuthenticationPresentationContextProviding?) {
        self.value = value
    }
}

private final class ASWebAuthenticationSessionBox: @unchecked Sendable {
    var session: ASWebAuthenticationSession?

    func cancel() {
        session?.cancel()
    }
}
#endif
