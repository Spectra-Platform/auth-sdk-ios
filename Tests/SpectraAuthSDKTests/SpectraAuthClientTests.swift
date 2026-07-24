import XCTest
@testable import SpectraAuthSDK

final class SpectraAuthClientTests: XCTestCase {
    func testStaticTokenProviderReturnsAccessToken() async throws {
        let client = SpectraAuthClient(
            configuration: configuration(),
            tokenProvider: StaticSpectraAccessTokenProvider(token: "dev-token")
        )

        let token = try await client.accessToken()

        XCTAssertEqual(token, "dev-token")
    }

    func testEmptyStaticTokenFailsClosed() async {
        let client = SpectraAuthClient(
            configuration: configuration(),
            tokenProvider: StaticSpectraAccessTokenProvider(token: " ")
        )

        do {
            _ = try await client.accessToken()
            XCTFail("Expected emptyAccessToken")
        } catch let error as SpectraAuthClientError {
            XCTAssertEqual(error, .emptyAccessToken)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInMemorySessionStoreProvidesCurrentUser() async throws {
        let user = SpectraAuthUser(appUserId: "user_123", projectId: "project_123", environment: .test)
        let session = SpectraAuthSession(
            accessToken: SpectraAuthAccessToken(
                token: "session-token",
                expiresAt: Date().addingTimeInterval(3600),
                user: user
            )
        )
        let store = InMemorySpectraAuthSessionStore(session: session)
        let client = SpectraAuthClient(configuration: configuration(), sessionStore: store)

        let currentUser = try await client.currentUser()
        let token = try await client.accessToken()
        XCTAssertEqual(currentUser, user)
        XCTAssertEqual(token, "session-token")
    }

    func testLogoutClearsSession() async throws {
        let user = SpectraAuthUser(appUserId: "user_123", projectId: "project_123", environment: .test)
        let store = InMemorySpectraAuthSessionStore(session: SpectraAuthSession(
            accessToken: SpectraAuthAccessToken(
                token: "session-token",
                expiresAt: Date().addingTimeInterval(3600),
                user: user
            )
        ))
        let client = SpectraAuthClient(configuration: configuration(), sessionStore: store)

        try await client.logout()

        let currentUser = try await client.currentUser()
        XCTAssertNil(currentUser)
    }

    func testMakePlatformRequestUsesProjectScopedPathAndHeaders() async throws {
        let client = SpectraAuthClient(
            configuration: configuration(),
            tokenProvider: StaticSpectraAccessTokenProvider(token: "dev-token")
        )

        let request = try await client.makePlatformRequest(
            method: "POST",
            path: "notification/devices/00000000-0000-4000-8000-000000000000",
            idempotencyKey: "idem-1"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.spectra.example/platform/v1/projects/project_123/notification/devices/00000000-0000-4000-8000-000000000000")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dev-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "idem-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Spectra-Public-Client-Id"), "app_public_123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Spectra-Environment"), "test")
    }

    private func configuration() -> SpectraAuthConfiguration {
        SpectraAuthConfiguration(
            baseURL: URL(string: "https://api.spectra.example")!,
            projectId: "project_123",
            publicClientId: "app_public_123",
            environment: .test
        )
    }
}
