import Foundation

public actor AuthClient: TokenProvider {
    public let configuration: AuthClientConfiguration

    private var session: AuthSession?
    private let refreshStrategy: any AuthTokenRefreshStrategy
    private let clock: any AuthClock

    public init(
        configuration: AuthClientConfiguration,
        initialSession: AuthSession? = nil,
        refreshStrategy: any AuthTokenRefreshStrategy = UnavailableAuthTokenRefreshStrategy(),
        clock: any AuthClock = SystemAuthClock()
    ) {
        self.configuration = configuration
        self.session = initialSession
        self.refreshStrategy = refreshStrategy
        self.clock = clock
    }

    public var currentUser: AppUser? {
        session?.user
    }

    public func getAccessToken(forceRefresh: Bool = false) async throws -> AccessToken {
        if !forceRefresh, let accessToken = session?.accessToken, !accessToken.isExpired(at: clock.now) {
            return accessToken
        }

        let refreshedSession = try await refreshStrategy.refreshToken(
            configuration: configuration,
            currentSession: session
        )
        session = refreshedSession
        return refreshedSession.accessToken
    }

    @discardableResult
    public func refresh() async throws -> AccessToken {
        try await getAccessToken(forceRefresh: true)
    }

    public func logout() async {
        session = nil
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
