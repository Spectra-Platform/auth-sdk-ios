import Foundation
import XCTest
@testable import SpectraAuthSDK

final class AuthClientTests: XCTestCase {
    func testReturnsCachedAccessTokenWhenItIsNotExpired() async throws {
        let refreshStrategy = RecordingRefreshStrategy(refreshedSession: .fixture(tokenValue: "refreshed"))
        let client = AuthClient(
            configuration: .fixture,
            initialSession: .fixture(tokenValue: "cached", expiresAt: Date(timeIntervalSince1970: 2_000)),
            refreshStrategy: refreshStrategy,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let token = try await client.getAccessToken()
        let callCount = await refreshStrategy.callCount

        XCTAssertEqual(token.value, "cached")
        XCTAssertEqual(callCount, 0)
    }

    func testRefreshesExpiredAccessToken() async throws {
        let refreshStrategy = RecordingRefreshStrategy(refreshedSession: .fixture(tokenValue: "refreshed"))
        let client = AuthClient(
            configuration: .fixture,
            initialSession: .fixture(tokenValue: "expired", expiresAt: Date(timeIntervalSince1970: 1_000)),
            refreshStrategy: refreshStrategy,
            clock: FixedClock(now: Date(timeIntervalSince1970: 2_000))
        )

        let token = try await client.getAccessToken()
        let callCount = await refreshStrategy.callCount

        XCTAssertEqual(token.value, "refreshed")
        XCTAssertEqual(callCount, 1)
    }

    func testAuthorizedRequestAttachesBearerHeader() async throws {
        let client = AuthClient(
            configuration: .fixture,
            initialSession: .fixture(tokenValue: "access-token", expiresAt: Date(timeIntervalSince1970: 2_000)),
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )
        let request = URLRequest(url: URL(string: "https://storage.example.test/v1/objects")!)

        let authorized = try await client.authorizedRequest(request)

        XCTAssertEqual(authorized.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testLogoutClearsCurrentUserAndMakesRefreshRequired() async throws {
        let client = AuthClient(
            configuration: .fixture,
            initialSession: .fixture(tokenValue: "access-token"),
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        await client.logout()

        let currentUser = await client.currentUser
        XCTAssertNil(currentUser)
        do {
            _ = try await client.getAccessToken()
            XCTFail("Expected refreshUnavailable after logout without a refresh strategy")
        } catch AuthError.refreshUnavailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor RecordingRefreshStrategy: AuthTokenRefreshStrategy {
    private(set) var callCount = 0
    private let refreshedSession: AuthSession

    init(refreshedSession: AuthSession) {
        self.refreshedSession = refreshedSession
    }

    func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        callCount += 1
        return refreshedSession
    }
}

private struct FixedClock: AuthClock {
    let now: Date
}

private extension AuthClientConfiguration {
    static let fixture = AuthClientConfiguration(
        baseURL: URL(string: "https://auth.example.test")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .test,
        redirectURI: URL(string: "spectra-example://auth/callback")
    )
}

private extension AuthSession {
    static func fixture(
        tokenValue: String,
        expiresAt: Date = Date(timeIntervalSince1970: 2_000)
    ) -> AuthSession {
        AuthSession(
            user: AppUser(id: "app_user_123", projectId: "project_123"),
            accessToken: AccessToken(
                value: tokenValue,
                expiresAt: expiresAt,
                scopes: ["storage.objects.read"],
                audience: ["storage"]
            )
        )
    }
}
