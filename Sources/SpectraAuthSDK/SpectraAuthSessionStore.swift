import Foundation

public protocol SpectraAuthSessionStoring: Sendable {
    func loadSession() async throws -> SpectraAuthSession?
    func saveSession(_ session: SpectraAuthSession) async throws
    func clearSession() async throws
}

public actor InMemorySpectraAuthSessionStore: SpectraAuthSessionStoring {
    private var session: SpectraAuthSession?

    public init(session: SpectraAuthSession? = nil) {
        self.session = session
    }

    public func loadSession() async throws -> SpectraAuthSession? {
        session
    }

    public func saveSession(_ session: SpectraAuthSession) async throws {
        self.session = session
    }

    public func clearSession() async throws {
        session = nil
    }
}

