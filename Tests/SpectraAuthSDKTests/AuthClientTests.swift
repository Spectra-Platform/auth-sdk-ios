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

    func testAppUserRefreshSessionStrategyCreatesRefreshesAndRevokesServerSession() async throws {
        let transport = QueueingTransport(responses: [
            .success(
                statusCode: 201,
                body: appUserSessionBody(
                    refreshToken: "spur_initial",
                    accessToken: "spau_initial_chat",
                    refreshExpiresAt: "2040-01-10T00:00:00.000Z",
                    accessExpiresAt: "2040-01-02T03:04:05.000Z",
                    sessionId: "00000000-0000-4000-8000-000000000101"
                )
            ),
            .success(
                statusCode: 201,
                body: appUserSessionBody(
                    refreshToken: "spur_rotated",
                    accessToken: "spau_rotated_chat",
                    refreshExpiresAt: "2040-01-20T00:00:00.000Z",
                    accessExpiresAt: "2040-01-02T03:19:05.000Z",
                    sessionId: "00000000-0000-4000-8000-000000000102"
                )
            ),
            .success(statusCode: 204, body: Data()),
        ])
        let strategy = AppUserRefreshSessionStrategy(
            service: .chat,
            refreshTtlSeconds: 2_592_000,
            accessTtlSeconds: 900,
            additionalHeaders: ["X-Spectra-Internal-Key": "redacted-local-dev-key"],
            appUserIdProvider: { "usr_123" },
            transport: transport,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )
        let cache = InMemoryAuthSessionCache()
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: strategy,
            sessionCache: cache,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)),
            defaultService: .chat
        )

        let initialToken = try await client.getAccessToken(for: .chat, forceRefresh: true)
        let rotatedToken = try await client.getAccessToken(for: .chat, forceRefresh: true)
        let cachedSession = try await cache.loadSession(for: .chat)
        await client.logout()
        let clearedSession = try await cache.loadSession(for: .chat)
        let requests = await transport.requests

        XCTAssertEqual(initialToken.value, "spau_initial_chat")
        XCTAssertEqual(rotatedToken.value, "spau_rotated_chat")
        XCTAssertEqual(cachedSession?.refreshToken?.value, "spur_rotated")
        XCTAssertNil(clearedSession)
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url?.path, "/internal/dev/v1/app-user-sessions")
        XCTAssertEqual(requests[1].url?.path, "/internal/dev/v1/app-user-sessions/refresh")
        XCTAssertEqual(requests[2].url?.path, "/internal/dev/v1/app-user-sessions/logout")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-Spectra-Internal-Key"), "redacted-local-dev-key")

        let createJSON = try jsonBody(from: requests[0])
        XCTAssertEqual(createJSON["project_id"] as? String, "project_123")
        XCTAssertEqual(createJSON["public_client_id"] as? String, "public_client_123")
        XCTAssertEqual(createJSON["environment"] as? String, "test")
        XCTAssertEqual(createJSON["service"] as? String, "chat")
        XCTAssertEqual(createJSON["app_user_id"] as? String, "usr_123")
        XCTAssertEqual(createJSON["refresh_ttl_seconds"] as? Int, 2_592_000)
        XCTAssertEqual(createJSON["access_ttl_seconds"] as? Int, 900)

        let refreshJSON = try jsonBody(from: requests[1])
        XCTAssertEqual(refreshJSON["refresh_token"] as? String, "spur_initial")
        XCTAssertEqual(refreshJSON["service"] as? String, "chat")
        XCTAssertEqual(refreshJSON["access_ttl_seconds"] as? Int, 900)

        let logoutJSON = try jsonBody(from: requests[2])
        XCTAssertEqual(logoutJSON["refresh_token"] as? String, "spur_rotated")
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

    func testCachesAccessTokensByService() async throws {
        let refreshStrategy = RecordingServiceRefreshStrategy(sessions: [
            .storage: .fixture(tokenValue: "storage-token", service: .storage),
            .notification: .fixture(tokenValue: "notification-token", service: .notification),
        ])
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: refreshStrategy,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let storage = try await client.getAccessToken(for: .storage)
        let notification = try await client.getAccessToken(for: .notification)
        let cachedStorage = try await client.getAccessToken(for: .storage)
        let callCounts = await refreshStrategy.callCounts

        XCTAssertEqual(storage.value, "storage-token")
        XCTAssertEqual(notification.value, "notification-token")
        XCTAssertEqual(cachedStorage.value, "storage-token")
        XCTAssertEqual(callCounts[.storage], 1)
        XCTAssertEqual(callCounts[.notification], 1)
    }

    func testForceRefreshOnlyRefreshesRequestedService() async throws {
        let refreshStrategy = RecordingServiceRefreshStrategy(sessions: [
            .storage: .fixture(tokenValue: "storage-token", service: .storage),
            .notification: .fixture(tokenValue: "notification-token", service: .notification),
        ])
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: refreshStrategy,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        _ = try await client.getAccessToken(for: .storage)
        _ = try await client.getAccessToken(for: .notification)
        let refreshedStorage = try await client.getAccessToken(for: .storage, forceRefresh: true)
        let cachedNotification = try await client.getAccessToken(for: .notification)
        let callCounts = await refreshStrategy.callCounts

        XCTAssertEqual(refreshedStorage.value, "storage-token")
        XCTAssertEqual(cachedNotification.value, "notification-token")
        XCTAssertEqual(callCounts[.storage], 2)
        XCTAssertEqual(callCounts[.notification], 1)
    }

    func testRejectsServiceTokenWithMismatchedAudience() async throws {
        let refreshStrategy = RecordingServiceRefreshStrategy(sessions: [
            .notification: .fixture(
                tokenValue: "wrong-audience-token",
                service: .notification,
                audience: ["storage"]
            ),
        ])
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: refreshStrategy,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        do {
            _ = try await client.getAccessToken(for: .notification)
            XCTFail("Expected invalidTokenResponse")
        } catch AuthError.invalidTokenResponse {
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

private actor RecordingServiceRefreshStrategy: ServiceAwareAuthTokenRefreshStrategy {
    private(set) var callCounts: [AuthService: Int] = [:]
    private let sessions: [AuthService: AuthSession]

    init(sessions: [AuthService: AuthSession]) {
        self.sessions = sessions
    }

    func refreshToken(
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        try await refreshToken(for: .storage, configuration: configuration, currentSession: currentSession)
    }

    func refreshToken(
        for service: AuthService,
        configuration: AuthClientConfiguration,
        currentSession: AuthSession?
    ) async throws -> AuthSession {
        callCounts[service, default: 0] += 1
        guard let session = sessions[service] else {
            throw AuthError.refreshUnavailable
        }
        return session
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

private actor QueueingTransport: AuthHTTPTransport {
    enum Response {
        case success(statusCode: Int, body: Data)
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw AuthError.invalidTokenResponse
        }
        let response = responses.removeFirst()
        switch response {
        case let .success(statusCode, body):
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: statusCode == 204 ? nil : ["Content-Type": "application/json"]
            )!
            return (body, http)
        }
    }
}

private func appUserSessionBody(
    refreshToken: String,
    accessToken: String,
    refreshExpiresAt: String,
    accessExpiresAt: String,
    sessionId: String,
    appUserId: String = "usr_123",
    projectId: String = "project_123",
    publicClientId: String = "public_client_123",
    service: String = "chat"
) -> Data {
    """
    {
      "data": {
        "refresh_token": "\(refreshToken)",
        "access_token": "\(accessToken)",
        "token_type": "Bearer",
        "refresh_expires_at": "\(refreshExpiresAt)",
        "access_expires_at": "\(accessExpiresAt)",
        "project_id": "\(projectId)",
        "environment": "test",
        "public_client_id": "\(publicClientId)",
        "app_user_id": "\(appUserId)",
        "session_id": "\(sessionId)",
        "scopes": ["chat.rooms.read", "chat.messages.read", "chat.messages.send", "chat.websocket"],
        "audiences": ["\(service)"],
        "experimental_surface": "internal_dev_app_user_session"
      }
    }
    """.data(using: .utf8)!
}

private func jsonBody(from request: URLRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
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
        expiresAt: Date = Date(timeIntervalSince1970: 3_000),
        service: AuthService = .storage,
        scopes: Set<String>? = nil,
        audience: Set<String>? = nil
    ) -> AuthSession {
        AuthSession(
            user: AppUser(id: "app_user_123", projectId: "project_123"),
            accessToken: AccessToken(
                value: tokenValue,
                expiresAt: expiresAt,
                scopes: scopes ?? defaultScopes(for: service),
                audience: audience ?? [service.rawValue]
            )
        )
    }

    private static func defaultScopes(for service: AuthService) -> Set<String> {
        switch service {
        case .storage:
            return ["storage.objects.read"]
        case .email:
            return ["email.send"]
        case .notification:
            return ["notification.devices.write"]
        case .chat:
            return ["chat.websocket"]
        case .call:
            return ["call.join"]
        }
    }
}
