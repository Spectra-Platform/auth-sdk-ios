# iOS AuthSDK Integration Guide

이 문서는 iOS 앱에서 `SpectraAuthSDK`를 로컬 Swift Package로 붙이고, 다른 SDK에 token provider로 전달하는 현재 기준을 설명한다.

## 1. Package 추가

현재는 Swift Package Manager registry 배포 전이므로 로컬 package로 연결한다.

Xcode 기준:

1. `File > Add Package Dependencies...`
2. `Add Local...`
3. `Spectra-Platform/auth-sdk-ios` 선택
4. app target에 `SpectraAuthSDK` product 추가

`Package.swift`를 사용하는 앱/샘플이면 다음처럼 local dependency를 둔다.

```swift
.package(path: "../Spectra-Platform/auth-sdk-ios")
```

## 2. 앱에 넣어도 되는 값

`AuthClientConfiguration`에는 공개 가능한 값만 넣는다.

```swift
import Foundation
import SpectraAuthSDK

let configuration = AuthClientConfiguration(
    baseURL: URL(string: "https://auth.spectra.kr")!,
    projectId: "project_xxx",
    publicClientId: "public_client_xxx",
    environment: .live,
    redirectURI: URL(string: "modocamp://spectra-auth/callback")
)
```

앱 bundle에 넣어도 되는 값:

- `baseURL`
- `projectId`
- `publicClientId`
- `environment`
- redirect URI

앱 bundle에 넣으면 안 되는 값:

- Project API token
- Console session cookie
- provider client secret
- Apple private key
- SMTP credential
- APNs `.p8`
- FCM private key

## 3. AuthClient 생성

운영 hosted login은 `SpectraAuthClient` alias와 `AuthClient` actor 확장을 사용한다. `SpectraAuthClient`는
기본 service를 `.auth`로 두며, 기본 `getAccessToken()`은 앱 backend bootstrap용 Auth session token을 반환한다.

```swift
let authClient = SpectraAuthClient(
    configuration: configuration,
    sessionStore: KeychainAuthSessionCache(account: "project_xxx:auth")
)
```

local 또는 staging QA에서는 `.custom(...)`으로 test base URL과 callback URI를 분리한다.

```swift
let testAuthClient = SpectraAuthClient(
    configuration: .custom(
        baseURL: URL(string: "http://127.0.0.1:8081")!,
        projectId: "project_xxx",
        publicClientId: "public_client_xxx",
        environment: .test,
        redirectURI: URL(string: "modocamp-dev://spectra-auth/callback")
    ),
    sessionStore: KeychainAuthSessionCache(account: "project_xxx:test-auth")
)
```

Google/Apple hosted login:

```swift
let session = try await authClient.signInWithGoogle(options: .init(
    prompt: .selectAccount,
    timeout: .seconds(300)
))

let appleSession = try await authClient.signInWithApple()
```

SwiftUI deep link routing은 custom scheme callback을 등록한 뒤 앱 진입점에서 forwarding한다.

```swift
.onOpenURL { url in
    Task {
        _ = try await authClient.handleCallback(url: url)
    }
}
```

테스트나 내부 dev bridge에서 이미 받은 session이 있으면 `initialSession`으로 주입할 수 있다.

```swift
let session = AuthSession(
    user: AppUser(id: "app_user_xxx", projectId: "project_xxx"),
    accessToken: AccessToken(
        value: "user_access_token",
        expiresAt: Date().addingTimeInterval(3600),
        scopes: ["storage.user_root.read"],
        audience: ["storage"]
    )
)

let authClient = AuthClient(
    configuration: configuration,
    initialSession: session
)
```

이 방식은 현재 slice에서 integration 테스트를 쉽게 하기 위한 경계다. 운영 social login 대체물로 취급하지 않는다.

Auth Platform public dev/mock session API를 직접 확인하려면 `PublicAppUserSessionStrategy`를 주입한다.

```swift
let publicDevAuthClient = AuthClient(
    configuration: .local(
        projectId: "project_xxx",
        publicClientId: "public_client_xxx",
        redirectURI: URL(string: "spectra-example://auth/callback")
    ),
    refreshStrategy: PublicAppUserSessionStrategy(
        service: .storage,
        sessionProvider: DevMockAppUserSessionProvider(
            providerSubject: "dev-user-1"
        )
    ),
    sessionCache: KeychainAuthSessionCache(
        account: "project_xxx:dev-user-1"
    )
)
```

이 strategy는 최초 요청에서 `POST /v1/app-user-sessions/dev-provider`를 호출하고, 이후 refresh/logout은
`POST /v1/app-user-sessions/refresh`, `POST /v1/app-user-sessions/logout`을 호출한다. `dev_mock`은 `.test`
환경에서만 쓰며 `.live` configuration에서는 SDK가 네트워크 호출 전 거부한다.

Auth Platform internal/dev bridge를 확인해야 하면 별도 internal strategy를 주입한다.

```swift
let emailAuthClient = AuthClient(
    configuration: configuration,
    refreshStrategy: AppUserAccessTokenRefreshStrategy(
        service: .email,
        additionalHeaders: ["X-Spectra-Internal-Key": "local-dev-only"],
        appUserIdProvider: { "app_user_xxx" }
    )
)
```

`additionalHeaders`의 internal key는 local/dev bridge 검증용이다. 운영 앱 bundle에는 internal key,
Project API token 또는 provider secret을 넣지 않는다.

## 4. Access token 조회

```swift
let token = try await authClient.getAccessToken()
```

`token`은 Auth session access token이며 Modo backend bootstrap bearer proof로 사용한다.

강제 refresh:

```swift
let refreshedToken = try await authClient.getAccessToken(forceRefresh: true)
let refreshedSession = try await authClient.refreshSession()
```

Storage/Chat/Notification 같은 service token은 명시적으로 service를 요청할 때만 발급한다. 이 token은 각 SDK
내부 요청용이며 Modo backend bootstrap에는 사용하지 않는다.

```swift
let chatToken = try await authClient.getAccessToken(.init(service: .chat))
```

기본 refresh strategy는 `AuthError.refreshUnavailable`을 반환한다. `HostedAuthSessionStrategy`와
`PublicAppUserSessionStrategy`는
Auth Platform Identity Plane의 public app-user session API를 통해 refresh token rotation을 처리한다.
service별 token 요청 중 refresh token이 회전되면 같은 `AuthClient` 안에서 해당 refresh session을 공유하던
다른 service cache에도 새 refresh token을 전파한다.

## 5. Authorized request 생성

다른 SDK나 앱 내부 client는 `TokenProvider`만 의존한다.

```swift
func makeStorageRequest(
    tokenProvider: any TokenProvider,
    url: URL
) async throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    return try await tokenProvider.authorizedRequest(request)
}
```

직접 header가 필요하면:

```swift
let header = try await authClient.authorizationHeader()
```

## 6. 다른 SDK에 주입

NotificationSDK는 현재 별도 `SpectraAccessTokenProviding` protocol을 사용한다. 앱에서는 얇은 adapter를 둔다.

```swift
import SpectraAuthSDK
import SpectraNotificationSDK

struct NotificationTokenProvider: SpectraAccessTokenProviding {
    let auth: any TokenProvider

    func accessToken() async throws -> String {
        try await auth.getAccessToken().value
    }
}

let notificationTokenProvider = NotificationTokenProvider(auth: authClient)
```

StorageSDK가 생기면 같은 방식으로 AuthSDK의 `TokenProvider`를 주입한다.

## 7. Logout

```swift
try await authClient.logout(
    endBrowserSession: true,
    postLogoutRedirectURI: URL(string: "modocamp://spectra-auth/logout-complete")
)
```

Hosted login, `PublicAppUserSessionStrategy` 또는 `AppUserRefreshSessionStrategy`처럼 revocation을 지원하는 strategy를 쓰면
SDK가 서버 logout endpoint를 호출한 뒤 in-memory session과 session cache를 지운다. 기본 strategy만 쓰는 경우에는
local state만 지운다.

## 현재 완료 상태

- Swift Package build/test
- `AuthClient`
- `TokenProvider`
- access token cache/expiry 경계
- authorized request helper
- public dev/mock app-user session create/refresh/logout
- service별 refresh token rotation propagation
- ASWebAuthenticationSession 기반 Google/Apple hosted login
- PKCE/state/nonce challenge와 authorization code exchange
- Auth session refresh/logout public endpoint
- safe error fields: `code`, `status`, `requestId`, `message`, `retryAfterSeconds`
- logout server revocation과 local state clear

## 아직 완료가 아닌 것

- Universal Link-only hosted login helper
- 실제 Modo Camp iOS app, iOS simulator, 실기기 Google/Apple provider E2E
