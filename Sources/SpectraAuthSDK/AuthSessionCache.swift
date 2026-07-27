import Foundation

public protocol AuthSessionCache: Sendable {
    func loadSession() async throws -> AuthSession?
    func storeSession(_ session: AuthSession) async throws
    func clearSession() async throws
}

public actor InMemoryAuthSessionCache: AuthSessionCache {
    private var session: AuthSession?

    public init(session: AuthSession? = nil) {
        self.session = session
    }

    public func loadSession() async throws -> AuthSession? {
        session
    }

    public func storeSession(_ session: AuthSession) async throws {
        self.session = session
    }

    public func clearSession() async throws {
        session = nil
    }
}
