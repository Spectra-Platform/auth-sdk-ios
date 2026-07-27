import Foundation

public actor AuthClient: ServiceTokenProvider {
    public let configuration: AuthClientConfiguration
    public let defaultService: AuthService

    private var sessionsByService: [AuthService: AuthSession]
    private let refreshStrategy: any AuthTokenRefreshStrategy
    private let sessionCache: (any AuthSessionCache)?
    private let clock: any AuthClock

    public init(
        configuration: AuthClientConfiguration,
        initialSession: AuthSession? = nil,
        refreshStrategy: any AuthTokenRefreshStrategy = UnavailableAuthTokenRefreshStrategy(),
        sessionCache: (any AuthSessionCache)? = nil,
        clock: any AuthClock = SystemAuthClock(),
        defaultService: AuthService? = nil
    ) {
        self.configuration = configuration
        self.defaultService = Self.resolveDefaultService(
            explicitDefaultService: defaultService,
            refreshStrategy: refreshStrategy,
            initialSession: initialSession
        )
        self.sessionsByService = Self.indexSessions(
            initialSession,
            defaultService: self.defaultService
        )
        self.refreshStrategy = refreshStrategy
        self.sessionCache = sessionCache
        self.clock = clock
    }

    public static func restoringCachedSession(
        configuration: AuthClientConfiguration,
        initialSession: AuthSession? = nil,
        refreshStrategy: any AuthTokenRefreshStrategy = UnavailableAuthTokenRefreshStrategy(),
        sessionCache: any AuthSessionCache,
        clock: any AuthClock = SystemAuthClock(),
        defaultService: AuthService? = nil
    ) async throws -> AuthClient {
        let validatedConfiguration = try configuration.validated()
        let resolvedDefaultService = resolveDefaultService(
            explicitDefaultService: defaultService,
            refreshStrategy: refreshStrategy,
            initialSession: initialSession
        )
        let restoredSession = try await loadCachedSession(
            from: sessionCache,
            for: resolvedDefaultService,
            allowLegacyFallback: true
        )
        let client = AuthClient(
            configuration: validatedConfiguration,
            initialSession: initialSession ?? restoredSession,
            refreshStrategy: refreshStrategy,
            sessionCache: sessionCache,
            clock: clock,
            defaultService: resolvedDefaultService
        )
        if let initialSession {
            try await client.storeInitialSessionInCache(initialSession)
        }
        return client
    }

    public var currentUser: AppUser? {
        sessionsByService[defaultService]?.user ?? sessionsByService.values.first?.user
    }

    public func getAccessToken(forceRefresh: Bool = false) async throws -> AccessToken {
        try await getAccessToken(
            for: defaultService,
            forceRefresh: forceRefresh,
            allowMissingAudience: true
        )
    }

    @discardableResult
    public func refresh() async throws -> AccessToken {
        try await getAccessToken(forceRefresh: true)
    }

    public func getAccessToken(for service: AuthService, forceRefresh: Bool = false) async throws -> AccessToken {
        try await getAccessToken(
            for: service,
            forceRefresh: forceRefresh,
            allowMissingAudience: false
        )
    }

    @discardableResult
    public func refresh(for service: AuthService) async throws -> AccessToken {
        try await getAccessToken(for: service, forceRefresh: true)
    }

    public func logout() async {
        if let revocationStrategy = refreshStrategy as? any AuthSessionRevocationStrategy {
            for session in uniqueRefreshSessions() {
                try? await revocationStrategy.revokeSession(
                    configuration: configuration,
                    session: session
                )
            }
        }
        sessionsByService.removeAll()
        try? await sessionCache?.clearSession()
        if let serviceCache = sessionCache as? any ServiceAuthSessionCache {
            for service in AuthService.allCases {
                try? await serviceCache.clearSession(for: service)
            }
        }
    }

    @discardableResult
    public func restoreSessionFromCache() async throws -> AuthSession? {
        try await restoreSessionFromCache(for: defaultService, allowLegacyFallback: true)
    }

    @discardableResult
    public func restoreSessionFromCache(for service: AuthService) async throws -> AuthSession? {
        try await restoreSessionFromCache(for: service, allowLegacyFallback: false)
    }

    private func getAccessToken(
        for service: AuthService,
        forceRefresh: Bool,
        allowMissingAudience: Bool
    ) async throws -> AccessToken {
        if !forceRefresh,
           let cachedSession = sessionsByService[service],
           cachedSession.accessToken.isValid(
               for: service,
               at: clock.now,
               allowMissingAudience: allowMissingAudience
           ) {
            return cachedSession.accessToken
        }

        _ = try configuration.validated()
        let refreshBaseSession = sessionForRefresh(for: service)
        let refreshedSession = try await refreshSession(
            for: service,
            currentSession: refreshBaseSession
        )
        guard refreshedSession.accessToken.isValid(
            for: service,
            at: clock.now,
            allowMissingAudience: allowMissingAudience
        ) else {
            throw AuthError.invalidTokenResponse
        }
        try await propagateRefreshTokenRotation(
            from: refreshBaseSession?.refreshToken,
            to: refreshedSession.refreshToken,
            refreshedService: service
        )
        sessionsByService[service] = refreshedSession
        try await storeCachedSession(refreshedSession, for: service)
        return refreshedSession.accessToken
    }

    private func refreshSession(
        for service: AuthService,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        if let serviceAwareRefreshStrategy = refreshStrategy as? any ServiceAwareAuthTokenRefreshStrategy {
            return try await serviceAwareRefreshStrategy.refreshToken(
                for: service,
                configuration: configuration,
                currentSession: currentSession
            )
        }
        if service == defaultService {
            return try await refreshStrategy.refreshToken(
                configuration: configuration,
                currentSession: currentSession
            )
        }
        throw AuthError.refreshUnavailable
    }

    private func sessionForRefresh(for service: AuthService) -> AuthSession? {
        if let currentSession = sessionsByService[service] {
            if let refreshToken = currentSession.refreshToken,
               refreshToken.isExpired(at: clock.now) {
                return reusableRefreshSession() ?? currentSession
            }
            return currentSession
        }
        return reusableRefreshSession()
    }

    private func reusableRefreshSession() -> AuthSession? {
        sessionsByService.values.first { session in
            guard let refreshToken = session.refreshToken else {
                return false
            }
            return !refreshToken.isExpired(at: clock.now)
        } ?? sessionsByService.values.first { session in
            session.refreshToken != nil
        }
    }

    private func propagateRefreshTokenRotation(
        from oldRefreshToken: AppUserRefreshToken?,
        to newRefreshToken: AppUserRefreshToken?,
        refreshedService: AuthService
    ) async throws {
        guard let oldRefreshToken,
              let newRefreshToken,
              oldRefreshToken != newRefreshToken else {
            return
        }

        let updatedSessions = sessionsByService.compactMap { service, session -> (AuthService, AuthSession)? in
            guard service != refreshedService,
                  session.refreshToken?.sessionId == oldRefreshToken.sessionId else {
                return nil
            }
            return (
                service,
                AuthSession(
                    user: session.user,
                    accessToken: session.accessToken,
                    refreshToken: newRefreshToken
                )
            )
        }
        for (service, updatedSession) in updatedSessions {
            sessionsByService[service] = updatedSession
            try await storeCachedSession(updatedSession, for: service)
        }
    }

    private func restoreSessionFromCache(
        for service: AuthService,
        allowLegacyFallback: Bool
    ) async throws -> AuthSession? {
        guard let sessionCache else {
            throw AuthError.sessionCacheUnavailable
        }
        let restoredSession = try await Self.loadCachedSession(
            from: sessionCache,
            for: service,
            allowLegacyFallback: allowLegacyFallback
        )
        if let restoredSession {
            let allowMissingAudience = allowLegacyFallback && service == defaultService
            guard restoredSession.accessToken.isValid(
                for: service,
                at: clock.now,
                allowMissingAudience: allowMissingAudience
            ) else {
                throw AuthError.invalidTokenResponse
            }
            sessionsByService[service] = restoredSession
        } else {
            sessionsByService[service] = nil
        }
        return restoredSession
    }

    public func clearSessionCache() async throws {
        guard let sessionCache else {
            throw AuthError.sessionCacheUnavailable
        }
        sessionsByService.removeAll()
        try await sessionCache.clearSession()
        if let serviceCache = sessionCache as? any ServiceAuthSessionCache {
            for service in AuthService.allCases {
                try await serviceCache.clearSession(for: service)
            }
        }
    }

    private func storeInitialSessionInCache(_ session: AuthSession) async throws {
        let service = primaryService(for: session)
        sessionsByService[service] = session
        try await storeCachedSession(session, for: service)
    }

    private func storeCachedSession(_ session: AuthSession, for service: AuthService) async throws {
        if let serviceCache = sessionCache as? any ServiceAuthSessionCache {
            try await serviceCache.storeSession(session, for: service)
        }
        if service == defaultService {
            try await sessionCache?.storeSession(session)
        }
    }

    private func primaryService(for session: AuthSession) -> AuthService {
        Self.primaryService(for: session, defaultService: defaultService)
    }

    private func uniqueRefreshSessions() -> [AuthSession] {
        var seen = Set<String>()
        return sessionsByService.values.filter { session in
            guard let refreshToken = session.refreshToken else {
                return false
            }
            return seen.insert(refreshToken.sessionId).inserted
        }
    }

    private static func loadCachedSession(
        from cache: any AuthSessionCache,
        for service: AuthService,
        allowLegacyFallback: Bool
    ) async throws -> AuthSession? {
        if let serviceCache = cache as? any ServiceAuthSessionCache,
           let serviceSession = try await serviceCache.loadSession(for: service) {
            return serviceSession
        }
        if allowLegacyFallback {
            return try await cache.loadSession()
        }
        return nil
    }

    private static func resolveDefaultService(
        explicitDefaultService: AuthService?,
        refreshStrategy: any AuthTokenRefreshStrategy,
        initialSession: AuthSession?
    ) -> AuthService {
        if let explicitDefaultService {
            return explicitDefaultService
        }
        if let serviceScopedRefreshStrategy = refreshStrategy as? any ServiceScopedAuthTokenRefreshStrategy {
            return serviceScopedRefreshStrategy.service
        }
        if let initialSession {
            return primaryService(for: initialSession, defaultService: .storage)
        }
        return .storage
    }

    private static func indexSessions(
        _ initialSession: AuthSession?,
        defaultService: AuthService
    ) -> [AuthService: AuthSession] {
        guard let initialSession else {
            return [:]
        }
        let services = initialSession.accessToken.audienceServices
        if services.isEmpty {
            return [defaultService: initialSession]
        }
        return Dictionary(uniqueKeysWithValues: services.map { ($0, initialSession) })
    }

    private static func primaryService(
        for session: AuthSession,
        defaultService: AuthService
    ) -> AuthService {
        session.accessToken.audienceServices.sorted { $0.rawValue < $1.rawValue }.first ?? defaultService
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
