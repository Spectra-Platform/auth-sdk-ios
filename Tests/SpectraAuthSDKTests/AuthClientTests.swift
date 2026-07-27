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

    func testAppUserAccessTokenRefreshStrategyRequestsOneServiceToken() async throws {
        let transport = RecordingTransport(response: .success(
            statusCode: 201,
            body: """
            {
              "data": {
                "access_token": "spau_test_email_token",
                "token_type": "Bearer",
                "expires_at": "2040-01-02T03:04:05.000Z",
                "project_id": "project_123",
                "environment": "test",
                "app_user_id": "usr_123",
                "session_id": "00000000-0000-4000-8000-000000000001",
                "scopes": ["email.send"],
                "audiences": ["email"],
                "experimental_surface": "internal_dev_app_user_email_token"
              }
            }
            """.data(using: .utf8)!
        ))
        let strategy = AppUserAccessTokenRefreshStrategy(
            service: .email,
            ttlSeconds: 900,
            additionalHeaders: ["X-Spectra-Internal-Key": "redacted-local-dev-key"],
            appUserIdProvider: { "usr_123" },
            transport: transport
        )
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: strategy,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let token = try await client.getAccessToken(forceRefresh: true)
        let request = await transport.lastRequest

        XCTAssertEqual(token.value, "spau_test_email_token")
        XCTAssertEqual(token.scopes, ["email.send"])
        XCTAssertEqual(token.audience, ["email"])
        XCTAssertEqual(request?.url?.absoluteString, "https://auth.example.test/internal/dev/v1/app-user-access-tokens")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Spectra-Internal-Key"), "redacted-local-dev-key")
        let body = try XCTUnwrap(request?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["project_id"] as? String, "project_123")
        XCTAssertEqual(json?["public_client_id"] as? String, "public_client_123")
        XCTAssertEqual(json?["environment"] as? String, "test")
        XCTAssertEqual(json?["service"] as? String, "email")
        XCTAssertEqual(json?["app_user_id"] as? String, "usr_123")
        XCTAssertEqual(json?["ttl_seconds"] as? Int, 900)
    }

    func testAppUserAccessTokenRefreshStrategyRejectsMismatchedAudience() async throws {
        let transport = RecordingTransport(response: .success(
            statusCode: 201,
            body: """
            {
              "data": {
                "access_token": "spau_test_storage_token",
                "token_type": "Bearer",
                "expires_at": "2040-01-02T03:04:05Z",
                "project_id": "project_123",
                "environment": "test",
                "app_user_id": "usr_123",
                "session_id": "00000000-0000-4000-8000-000000000001",
                "scopes": ["storage.user_root.read"],
                "audiences": ["storage"]
              }
            }
            """.data(using: .utf8)!
        ))
        let strategy = AppUserAccessTokenRefreshStrategy(
            service: .email,
            appUserIdProvider: { "usr_123" },
            transport: transport
        )
        let client = AuthClient(configuration: .fixture, refreshStrategy: strategy)

        do {
            _ = try await client.refresh()
            XCTFail("Expected invalidTokenResponse")
        } catch AuthError.invalidTokenResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthServiceIncludesChatAndCallAudiences() {
        XCTAssertEqual(AuthService.chat.rawValue, "chat")
        XCTAssertEqual(AuthService.call.rawValue, "call")
    }

    func testConfigurationPresetsKeepExistingInitializerCompatible() throws {
        let local = AuthClientConfiguration.local(
            projectId: "project_123",
            publicClientId: "public_client_123"
        )
        let live = AuthClientConfiguration.live(
            projectId: "project_123",
            publicClientId: "public_client_123",
            redirectURI: URL(string: "spectra://callback")
        )
        let custom = AuthClientConfiguration.custom(
            baseURL: URL(string: "https://auth.custom.test")!,
            projectId: "project_123",
            publicClientId: "public_client_123",
            environment: .test
        )
        let existingInitializer = AuthClientConfiguration(
            baseURL: URL(string: "https://auth.example.test")!,
            projectId: "project_123",
            publicClientId: "public_client_123",
            environment: .test
        )

        XCTAssertEqual(local.baseURL.absoluteString, "http://127.0.0.1:8081")
        XCTAssertEqual(local.environment, .test)
        XCTAssertEqual(live.baseURL.absoluteString, "https://auth.spectra.kr")
        XCTAssertEqual(live.environment, .live)
        XCTAssertEqual(live.redirectURI?.absoluteString, "spectra://callback")
        XCTAssertEqual(custom.baseURL.absoluteString, "https://auth.custom.test")
        XCTAssertEqual(try existingInitializer.validated(), existingInitializer)
    }

    func testConfigurationValidationReportsReadableError() {
        let configuration = AuthClientConfiguration(
            baseURL: URL(string: "relative/path")!,
            projectId: " ",
            publicClientId: "public_client_123",
            environment: .test
        )

        do {
            _ = try configuration.validated()
            XCTFail("Expected invalidConfiguration")
        } catch let AuthError.invalidConfigurationReason(reason) {
            XCTAssertTrue(reason.contains("baseURL"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestoringCachedSessionUsesStoredSessionWithoutRefresh() async throws {
        let cache = InMemoryAuthSessionCache(session: .fixture(tokenValue: "cached-from-cache"))
        let refreshStrategy = RecordingRefreshStrategy(refreshedSession: .fixture(tokenValue: "refreshed"))

        let client = try await AuthClient.restoringCachedSession(
            configuration: .fixture,
            refreshStrategy: refreshStrategy,
            sessionCache: cache,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let token = try await client.getAccessToken()
        let callCount = await refreshStrategy.callCount

        XCTAssertEqual(token.value, "cached-from-cache")
        XCTAssertEqual(callCount, 0)
    }

    func testRefreshStoresSessionInCache() async throws {
        let cache = InMemoryAuthSessionCache()
        let refreshed = AuthSession.fixture(
            tokenValue: "refreshed-and-cached",
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: RecordingRefreshStrategy(refreshedSession: refreshed),
            sessionCache: cache,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let token = try await client.refresh()
        let cached = try await cache.loadSession()

        XCTAssertEqual(token.value, "refreshed-and-cached")
        XCTAssertEqual(cached, refreshed)
    }

    func testRestoreSessionFromCacheUpdatesCurrentUser() async throws {
        let cache = InMemoryAuthSessionCache(session: .fixture(tokenValue: "cached-from-cache"))
        let client = AuthClient(
            configuration: .fixture,
            sessionCache: cache,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let restored = try await client.restoreSessionFromCache()
        let currentUser = await client.currentUser

        XCTAssertEqual(restored?.accessToken.value, "cached-from-cache")
        XCTAssertEqual(currentUser?.id, "app_user_123")
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

private actor RecordingTransport: AuthHTTPTransport {
    enum Response {
        case success(statusCode: Int, body: Data)
    }

    private(set) var lastRequest: URLRequest?
    private let response: Response

    init(response: Response) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        switch response {
        case let .success(statusCode, body):
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, http)
        }
    }
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
