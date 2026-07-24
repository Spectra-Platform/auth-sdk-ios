import Foundation

public protocol SpectraAccessTokenProviding: Sendable {
    func accessToken() async throws -> String
}

public struct StaticSpectraAccessTokenProvider: SpectraAccessTokenProviding {
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func accessToken() async throws -> String {
        token
    }
}

