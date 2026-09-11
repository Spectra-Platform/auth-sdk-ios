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

    func testPublicAppUserSessionStrategyCreatesRefreshesRotatesAndLogsOut() async throws {
        let transport = QueueingTransport(responses: [
            .success(
                statusCode: 201,
                body: appUserSessionBody(
                    refreshToken: "spur_public_initial",
                    accessToken: "jwt_public_storage_initial",
                    refreshExpiresAt: "2040-01-10T00:00:00.000Z",
                    accessExpiresAt: "2040-01-02T03:04:05.000Z",
                    sessionId: "00000000-0000-4000-8000-000000000201",
                    appUserId: "usr_public_123",
                    service: "storage"
                )
            ),
            .success(
                statusCode: 201,
                body: appUserSessionBody(
                    refreshToken: "spur_public_email_rotated",
                    accessToken: "jwt_public_email",
                    refreshExpiresAt: "2040-01-20T00:00:00.000Z",
                    accessExpiresAt: "2040-01-02T03:19:05.000Z",
                    sessionId: "00000000-0000-4000-8000-000000000202",
                    appUserId: "usr_public_123",
                    service: "email"
                )
            ),
            .success(
                statusCode: 201,
                body: appUserSessionBody(
                    refreshToken: "spur_public_storage_rotated",
                    accessToken: "jwt_public_storage_rotated",
                    refreshExpiresAt: "2040-01-30T00:00:00.000Z",
                    accessExpiresAt: "2040-01-02T03:34:05.000Z",
                    sessionId: "00000000-0000-4000-8000-000000000203",
                    appUserId: "usr_public_123",
                    service: "storage"
                )
            ),
            .success(statusCode: 204, body: Data()),
        ])
        let strategy = PublicAppUserSessionStrategy(
            service: .storage,
            sessionProvider: DevMockAppUserSessionProvider(providerSubject: "dev-user-1"),
            accessTtlSeconds: 900,
            transport: transport,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )
        let cache = InMemoryAuthSessionCache()
        let client = AuthClient(
            configuration: .fixture,
            refreshStrategy: strategy,
            sessionCache: cache,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)),
            defaultService: .storage
        )

        let initialStorageToken = try await client.getAccessToken(for: .storage, forceRefresh: true)
        let emailToken = try await client.getAccessToken(for: .email, forceRefresh: true)
        let rotatedStorageToken = try await client.getAccessToken(for: .storage, forceRefresh: true)
        let cachedStorageSession = try await cache.loadSession(for: .storage)
        let cachedEmailSession = try await cache.loadSession(for: .email)
        await client.logout()
        let clearedStorageSession = try await cache.loadSession(for: .storage)
        let clearedEmailSession = try await cache.loadSession(for: .email)
        let requests = await transport.requests

        XCTAssertEqual(initialStorageToken.value, "jwt_public_storage_initial")
        XCTAssertEqual(emailToken.value, "jwt_public_email")
        XCTAssertEqual(rotatedStorageToken.value, "jwt_public_storage_rotated")
        XCTAssertEqual(cachedStorageSession?.refreshToken?.value, "spur_public_storage_rotated")
        XCTAssertEqual(cachedEmailSession?.refreshToken?.value, "spur_public_storage_rotated")
        XCTAssertNil(clearedStorageSession)
        XCTAssertNil(clearedEmailSession)
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].url?.path, "/v1/app-user-sessions/dev-provider")
        XCTAssertEqual(requests[1].url?.path, "/v1/app-user-sessions/refresh")
        XCTAssertEqual(requests[2].url?.path, "/v1/app-user-sessions/refresh")
        XCTAssertEqual(requests[3].url?.path, "/v1/app-user-sessions/logout")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "X-Spectra-Internal-Key"))
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "X-Spectra-Internal-Key"))

        let createJSON = try jsonBody(from: requests[0])
        XCTAssertEqual(createJSON["project_id"] as? String, "project_123")
        XCTAssertEqual(createJSON["public_client_id"] as? String, "public_client_123")
        XCTAssertEqual(createJSON["environment"] as? String, "test")
        XCTAssertEqual(createJSON["provider"] as? String, "dev_mock")
        XCTAssertEqual(createJSON["provider_subject"] as? String, "dev-user-1")
        XCTAssertEqual(createJSON["service"] as? String, "storage")
        XCTAssertNil(createJSON["access_ttl_seconds"])
        XCTAssertNil(createJSON["refresh_ttl_seconds"])

        let emailRefreshJSON = try jsonBody(from: requests[1])
        XCTAssertEqual(emailRefreshJSON["refresh_token"] as? String, "spur_public_initial")
        XCTAssertEqual(emailRefreshJSON["service"] as? String, "email")
        XCTAssertEqual(emailRefreshJSON["access_ttl_seconds"] as? Int, 900)

        let storageRefreshJSON = try jsonBody(from: requests[2])
        XCTAssertEqual(storageRefreshJSON["refresh_token"] as? String, "spur_public_email_rotated")
        XCTAssertEqual(storageRefreshJSON["service"] as? String, "storage")
        XCTAssertEqual(storageRefreshJSON["access_ttl_seconds"] as? Int, 900)

        let logoutJSON = try jsonBody(from: requests[3])
        XCTAssertEqual(logoutJSON["refresh_token"] as? String, "spur_public_storage_rotated")
    }

    func testDevMockSessionProviderRejectsLiveEnvironmentBeforeNetworkCall() async throws {
        let transport = QueueingTransport(responses: [])
        let strategy = PublicAppUserSessionStrategy(
            service: .storage,
            sessionProvider: DevMockAppUserSessionProvider(providerSubject: "dev-user-1"),
            transport: transport
        )
        let client = AuthClient(
            configuration: .liveFixture,
            refreshStrategy: strategy
        )

        do {
            _ = try await client.getAccessToken(for: .storage, forceRefresh: true)
            XCTFail("Expected dev_mock provider to reject live configuration")
        } catch let AuthError.invalidConfigurationReason(reason) {
            XCTAssertTrue(reason.contains("dev_mock"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
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

    func testHostedGoogleSignInCreatesChallengeOpensAuthorizationUrlAndStoresAuthSession() async throws {
        let transport = QueueingTransport(responses: [
            .success(
                statusCode: 201,
                body: """
                {
                  "data": {
                    "challenge_id": "challenge_123",
                    "state": "state_123",
                    "nonce": "nonce_123",
                    "expires_at": "2040-01-01T00:00:00.000Z"
                  }
                }
                """.data(using: .utf8)!
            ),
            .success(
                statusCode: 201,
                body: authSessionBody(
                    accessToken: "auth_access",
                    refreshToken: "auth_refresh",
                    appUserId: "app_user_hosted",
                    isNewAppUser: true,
                    expiresIn: 900,
                    refreshExpiresIn: 2_592_000
                )
            ),
        ])
        let cache = InMemoryAuthSessionCache()
        let webAuth = MockWebAuthenticationSessionProvider()
        let client = AuthClient(
            configuration: .fixture,
            sessionStore: cache,
            transport: transport,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
        )

        let session = try await client.signInWithGoogle(options: SpectraAuthSignInOptions(
            prompt: .selectAccount,
            timeout: .seconds(5),
            webAuthenticationSessionProvider: webAuth
        ))
        let accessToken = try await client.getAccessToken(SpectraGetAccessTokenOptions())
        let cached = try await cache.loadSession()
        let requests = await transport.requests
        let authorizationURL = await webAuth.authorizationURL

        XCTAssertEqual(session.user.id, "app_user_hosted")
        XCTAssertEqual(session.accessToken.value, "auth_access")
        XCTAssertEqual(session.accessToken.audience, [])
        XCTAssertEqual(session.isNewAppUser, true)
        XCTAssertEqual(accessToken.value, "auth_access")
        XCTAssertEqual(cached?.accessToken.value, "auth_access")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/platform/v1/auth/social/challenges")
        XCTAssertEqual(requests[1].url?.path, "/platform/v1/auth/social/exchanges")

        let challengeJSON = try jsonBody(from: requests[0])
        XCTAssertEqual(challengeJSON["project_id"] as? String, "project_123")
        XCTAssertEqual(challengeJSON["public_client_id"] as? String, "public_client_123")
        XCTAssertEqual(challengeJSON["provider"] as? String, "google")
        XCTAssertEqual(challengeJSON["redirect_uri"] as? String, "spectra-example://auth/callback")
        XCTAssertEqual(challengeJSON["pkce_challenge_method"] as? String, "S256")
        XCTAssertNotNil(challengeJSON["pkce_challenge"] as? String)

        let authComponents = try XCTUnwrap(URLComponents(
            url: try XCTUnwrap(authorizationURL),
            resolvingAgainstBaseURL: false
        ))
        let authQuery = queryDictionary(authComponents)
        XCTAssertEqual(authComponents.path, "/realms/platform-test/protocol/openid-connect/auth")
        XCTAssertEqual(authQuery["client_id"], "public_client_123")
        XCTAssertEqual(authQuery["redirect_uri"], "spectra-example://auth/callback")
        XCTAssertEqual(authQuery["state"], "state_123")
        XCTAssertEqual(authQuery["nonce"], "nonce_123")
        XCTAssertEqual(authQuery["code_challenge"], challengeJSON["pkce_challenge"] as? String)
        XCTAssertEqual(authQuery["code_challenge_method"], "S256")
        XCTAssertEqual(authQuery["prompt"], "select_account")
        XCTAssertEqual(authQuery["kc_idp_hint"]?.hasPrefix("spectra-test-google-"), true)

        let exchangeJSON = try jsonBody(from: requests[1])
        XCTAssertEqual(exchangeJSON["challenge_id"] as? String, "challenge_123")
        XCTAssertEqual(exchangeJSON["project_id"] as? String, "project_123")
        XCTAssertEqual(exchangeJSON["public_client_id"] as? String, "public_client_123")
        XCTAssertEqual(exchangeJSON["provider"] as? String, "google")
        XCTAssertEqual(exchangeJSON["redirect_uri"] as? String, "spectra-example://auth/callback")
        XCTAssertNotNil(exchangeJSON["pkce_verifier"] as? String)
        let credential = try XCTUnwrap(exchangeJSON["credential"] as? [String: Any])
        XCTAssertEqual(credential["kind"] as? String, "authorization_code")
        XCTAssertEqual(credential["authorization_code"] as? String, "code_from_browser")
    }

    func testHostedServiceTokenUsesAuthSessionTokenAndKeepsAuthTokenBoundary() async throws {
        let transport = QueueingTransport(responses: [
            .success(
                statusCode: 201,
                body: serviceTokenBody(
                    accessToken: "chat_service_access",
                    service: "chat"
                )
            ),
        ])
        let client = AuthClient(
            configuration: .fixture,
            initialSession: .hostedFixture(
                accessToken: "auth_bootstrap_access",
                refreshToken: "auth_refresh"
            ),
            refreshStrategy: HostedAuthSessionStrategy(
                transport: transport,
                clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
            ),
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)),
            defaultService: .auth
        )

        let authToken = try await client.getAccessToken(SpectraGetAccessTokenOptions())
        let chatToken = try await client.getAccessToken(SpectraGetAccessTokenOptions(service: .chat))
        let requests = await transport.requests

        XCTAssertEqual(authToken.value, "auth_bootstrap_access")
        XCTAssertEqual(authToken.audience, [])
        XCTAssertEqual(chatToken.value, "chat_service_access")
        XCTAssertEqual(chatToken.audience, ["chat"])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/platform/v1/auth/sessions/current/access-tokens")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer auth_bootstrap_access")
        XCTAssertEqual((try jsonBody(from: requests[0]))["service"] as? String, "chat")
    }

    func testHostedRefreshAndLogoutUsePublicAuthSessionEndpoints() async throws {
        let transport = QueueingTransport(responses: [
            .success(
                statusCode: 200,
                body: authSessionBody(
                    accessToken: "auth_access_refreshed",
                    refreshToken: "auth_refresh_rotated",
                    expiresIn: 900,
                    refreshExpiresIn: 2_592_000
                )
            ),
            .success(statusCode: 204, body: Data()),
        ])
        let cache = InMemoryAuthSessionCache()
        let client = AuthClient(
            configuration: .fixture,
            initialSession: .hostedFixture(
                accessToken: "auth_access_expired",
                refreshToken: "auth_refresh",
                expiresAt: Date(timeIntervalSince1970: 900)
            ),
            refreshStrategy: HostedAuthSessionStrategy(
                transport: transport,
                clock: FixedClock(now: Date(timeIntervalSince1970: 1_000))
            ),
            sessionCache: cache,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_000)),
            defaultService: .auth
        )

        let refreshed = try await client.refreshSession()
        try await client.logout(endBrowserSession: false)
        let requests = await transport.requests
        let cached = try await cache.loadSession()

        XCTAssertEqual(refreshed.accessToken.value, "auth_access_refreshed")
        XCTAssertEqual(refreshed.refreshToken?.value, "auth_refresh_rotated")
        XCTAssertNil(cached)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/platform/v1/auth/sessions/refresh")
        XCTAssertEqual(requests[1].url?.path, "/platform/v1/auth/sessions/current")
        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer auth_access_refreshed")
        XCTAssertEqual((try jsonBody(from: requests[0]))["refresh_token"] as? String, "auth_refresh")
        XCTAssertEqual((try jsonBody(from: requests[1]))["refresh_token"] as? String, "auth_refresh_rotated")
    }

    func testHostedCallbackRejectsMismatchedState() async throws {
        let client = AuthClient(
            configuration: .fixture,
            sessionStore: InMemoryAuthSessionCache()
        )
        await client.setPendingHostedSignIn(SpectraAuthPendingSignIn(
            provider: .apple,
            redirectURI: URL(string: "spectra-example://auth/callback")!,
            challengeId: "challenge_123",
            state: "expected_state",
            nonce: "nonce_123",
            pkceVerifier: "verifier_123"
        ))

        do {
            _ = try await client.handleCallback(url: URL(string: "spectra-example://auth/callback?code=code_from_browser&state=wrong_state")!)
            XCTFail("Expected callback mismatch")
        } catch let AuthError.requestFailed(code, _, _, _, _) {
            XCTAssertEqual(code, "SIGN_IN_CALLBACK_MISMATCH")
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

private actor MockWebAuthenticationSessionProvider: SpectraWebAuthenticationSessionProvider {
    private(set) var authorizationURL: URL?

    func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String?,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL {
        self.authorizationURL = authorizationURL
        let components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        let state = components?.queryItems?.first { $0.name == "state" }?.value ?? ""
        return URL(string: "spectra-example://auth/callback?code=code_from_browser&state=\(state)")!
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

private func authSessionBody(
    accessToken: String,
    refreshToken: String,
    appUserId: String = "app_user_123",
    projectId: String = "project_123",
    isNewAppUser: Bool = false,
    expiresIn: Int,
    refreshExpiresIn: Int
) -> Data {
    """
    {
      "data": {
        "access_token": "\(accessToken)",
        "refresh_token": "\(refreshToken)",
        "app_user_id": "\(appUserId)",
        "project_id": "\(projectId)",
        "is_new_app_user": \(isNewAppUser),
        "expires_in": \(expiresIn),
        "refresh_expires_in": \(refreshExpiresIn),
        "token_type": "Bearer",
        "user": {
          "display_name": "Test User"
        }
      }
    }
    """.data(using: .utf8)!
}

private func serviceTokenBody(
    accessToken: String,
    service: String,
    projectId: String = "project_123",
    appUserId: String = "app_user_123"
) -> Data {
    """
    {
      "data": {
        "access_token": "\(accessToken)",
        "token_type": "Bearer",
        "expires_at": "2040-01-02T03:04:05.000Z",
        "project_id": "\(projectId)",
        "environment": "test",
        "app_user_id": "\(appUserId)",
        "session_id": "00000000-0000-4000-8000-000000000301",
        "scopes": ["\(service).read"],
        "audiences": ["\(service)"]
      }
    }
    """.data(using: .utf8)!
}

private func jsonBody(from request: URLRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func queryDictionary(_ components: URLComponents) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private extension AuthClientConfiguration {
    static let fixture = AuthClientConfiguration(
        baseURL: URL(string: "https://auth.example.test")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .test,
        redirectURI: URL(string: "spectra-example://auth/callback")
    )

    static let liveFixture = AuthClientConfiguration(
        baseURL: URL(string: "https://auth.example.test")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .live,
        redirectURI: URL(string: "spectra-example://auth/callback")
    )
}

private extension AuthSession {
    static func hostedFixture(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date = Date(timeIntervalSince1970: 3_000)
    ) -> AuthSession {
        AuthSession(
            user: AppUser(id: "app_user_123", projectId: "project_123"),
            accessToken: AccessToken(
                value: accessToken,
                expiresAt: expiresAt,
                scopes: [],
                audience: []
            ),
            refreshToken: AppUserRefreshToken(
                value: refreshToken,
                expiresAt: Date(timeIntervalSince1970: 4_000),
                sessionId: "auth_session_123"
            )
        )
    }

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
        case .auth:
            return []
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
