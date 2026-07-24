import Foundation

public enum SpectraAuthEnvironment: String, Sendable, Codable, Equatable {
    case test
    case live
}

public struct SpectraAuthConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let projectId: String
    public let publicClientId: String
    public let environment: SpectraAuthEnvironment

    public init(
        baseURL: URL,
        projectId: String,
        publicClientId: String,
        environment: SpectraAuthEnvironment
    ) {
        self.baseURL = baseURL
        self.projectId = projectId
        self.publicClientId = publicClientId
        self.environment = environment
    }
}

