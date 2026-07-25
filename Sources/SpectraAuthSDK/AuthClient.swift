import Foundation

public actor AuthClient: TokenProvider {
    public let configuration: AuthClientConfiguration

    private var session: AuthSession?
    private let refreshStrategy: any AuthTokenRefreshStrategy
    private let sessionCache: (any AuthSessionCache)?
    private let clock: any AuthClock

    public init(
        configuration: AuthClientConfiguration,
        initialSession: AuthSession? = nil,
        refreshStrategy: any AuthTokenRefreshStrategy = UnavailableAuthTokenRefreshStrategy(),
        sessionCache: (any AuthSessionCache)? = nil,
        clock: any AuthClock = SystemAuthClock()
    ) {
        self.configuration = configuration
        self.session = initialSession
        self.refreshStrategy = refreshStrategy
        self.sessionCache = sessionCache
        self.clock = clock
    }

    public static func restoringCachedSession(
        configuration: AuthClientConfiguration,
        initialSession: AuthSession? = nil,
        refreshStrategy: any AuthTokenRefreshStrategy = UnavailableAuthTokenRefreshStrategy(),
        sessionCache: any AuthSessionCache,
        clock: any AuthClock = SystemAuthClock()
    ) async throws -> AuthClient {
        let validatedConfiguration = try configuration.validated()
        let restoredSession = try await sessionCache.loadSession()
        let client = AuthClient(
            configuration: validatedConfiguration,
            initialSession: initialSession ?? restoredSession,
            refreshStrategy: refreshStrategy,
            sessionCache: sessionCache,
            clock: clock
        )
        if let initialSession {
            try await sessionCache.storeSession(initialSession)
        }
        return client
    }

    public var currentUser: AppUser? {
        session?.user
    }

    public func getAccessToken(forceRefresh: Bool = false) async throws -> AccessToken {
        if !forceRefresh, let accessToken = session?.accessToken, !accessToken.isExpired(at: clock.now) {
            return accessToken
        }

        _ = try configuration.validated()
        let refreshedSession = try await refreshStrategy.refreshToken(
            configuration: configuration,
            currentSession: session
        )
        session = refreshedSession
        try await sessionCache?.storeSession(refreshedSession)
        return refreshedSession.accessToken
    }

    @discardableResult
    public func refresh() async throws -> AccessToken {
        try await getAccessToken(forceRefresh: true)
    }

    public func logout() async {
        session = nil
        try? await sessionCache?.clearSession()
    }

    @discardableResult
    public func restoreSessionFromCache() async throws -> AuthSession? {
        guard let sessionCache else {
            throw AuthError.sessionCacheUnavailable
        }
        let restoredSession = try await sessionCache.loadSession()
        session = restoredSession
        return restoredSession
    }

    public func clearSessionCache() async throws {
        guard let sessionCache else {
            throw AuthError.sessionCacheUnavailable
        }
        session = nil
        try await sessionCache.clearSession()
    }
}

public struct UnavailableAuthTokenRefreshStrategy: AuthTokenRefreshStrategy {
    public init() {}

    public func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        throw AuthError.refreshUnavailable
    }
}
