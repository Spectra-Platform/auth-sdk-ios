import Foundation

public protocol AuthSessionCache: Sendable {
    func loadSession() async throws -> AuthSession?
    func storeSession(_ session: AuthSession) async throws
    func clearSession() async throws
}

public protocol ServiceAuthSessionCache: AuthSessionCache {
    func loadSession(for service: AuthService) async throws -> AuthSession?
    func storeSession(_ session: AuthSession, for service: AuthService) async throws
    func clearSession(for service: AuthService) async throws
}

public actor InMemoryAuthSessionCache: ServiceAuthSessionCache {
    private var session: AuthSession?
    private var serviceSessions: [AuthService: AuthSession]

    public init(
        session: AuthSession? = nil,
        serviceSessions: [AuthService: AuthSession] = [:]
    ) {
        self.session = session
        self.serviceSessions = serviceSessions
    }

    public func loadSession() async throws -> AuthSession? {
        session
    }

    public func storeSession(_ session: AuthSession) async throws {
        self.session = session
    }

    public func clearSession() async throws {
        session = nil
        serviceSessions.removeAll()
    }

    public func loadSession(for service: AuthService) async throws -> AuthSession? {
        serviceSessions[service]
    }

    public func storeSession(_ session: AuthSession, for service: AuthService) async throws {
        serviceSessions[service] = session
    }

    public func clearSession(for service: AuthService) async throws {
        serviceSessions[service] = nil
    }
}
