import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SpectraAuthTransportResponse: Sendable, Equatable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol SpectraAuthTransport: Sendable {
    func send(_ request: URLRequest) async throws -> SpectraAuthTransportResponse
}

public struct URLSessionSpectraAuthTransport: SpectraAuthTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> SpectraAuthTransportResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpectraAuthClientError.invalidResponse
        }
        return SpectraAuthTransportResponse(statusCode: http.statusCode, data: data)
    }
}

