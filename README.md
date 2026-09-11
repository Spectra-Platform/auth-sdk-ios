# Spectra AuthSDK for iOS

Swift Package 기반의 Spectra Platform iOS Auth SDK다. 이 저장소의 첫 구현 slice는 앱이 공개 가능한 Project/App Client 설정으로 `AuthClient`를 만들고, StorageSDK·NotificationSDK 같은 개별 SDK가 `TokenProvider`를 주입받아 사용자 bearer token을 요청에 붙일 수 있는 최소 경계를 제공한다. Core SDK는 먼저 만들지 않고, Auth/Notification/Storage/Chat/Call 같은 개별 SDK가 안정된 뒤 이들을 조합하는 통합 진입점으로 설계한다.

## 현재 구현 상태

- Swift Package: `SpectraAuthSDK`
- Package URL: `https://github.com/Spectra-Platform/auth-sdk-ios.git`
- Public configuration: `baseURL`, `projectId`, `publicClientId`, `environment`, `redirectURI`
- Public token provider: `TokenProvider`, `ServiceTokenProvider`, `AuthClient`, `AccessToken`, `AuthSession`, `AppUser`, `AppUserRefreshToken`
- Hosted social login: `SpectraAuthClient`, `SpectraAuthProvider`, `SpectraAuthSignInOptions`, `SpectraGetAccessTokenOptions`,
  `HostedAuthSessionStrategy`, `ASWebAuthenticationSessionProvider`
- Request helper: `authorizationHeader(forceRefresh:)`, `authorizedRequest(_:forceRefresh:)`
- Refresh boundary: `AuthTokenRefreshStrategy`, `PublicAppUserSessionStrategy`, `AppUserSessionProvider`, `DevMockAppUserSessionProvider`, `AppUserAccessTokenRefreshStrategy`, `AppUserRefreshSessionStrategy`
- Environment helpers: `AuthClientConfiguration.live(...)`, `.local(...)`, `.custom(...)`
- Session cache boundary: `AuthSessionCache`, `ServiceAuthSessionCache`, `InMemoryAuthSessionCache`, `KeychainAuthSessionCache`
- 검증: `swift test`

`AuthClient`는 앱이 직접 쓰기 쉬운 `TokenProvider` API와 개별 SDK 패키지가 필요한 기능별 token을 요청할 수 있는
low-level `ServiceTokenProvider` API를 함께 제공한다. 앱 화면 코드는 보통 `authClient`를 각 SDK에 주입하기만 하고,
내부 token 교환 값을 직접 다루지 않는다. StorageSDK·NotificationSDK·ChatSDK·CallSDK는 같은 Auth 객체를 공유하되
각 패키지 내부에서 필요한 기능 token을 요청하고 cache한다.

`HostedAuthSessionStrategy`는 Auth Platform의 production hosted login API를 호출한다. Google/Apple 로그인은
`ASWebAuthenticationSession`으로 Keycloak hosted authorization URL을 열고, SDK가 PKCE/state/nonce challenge를 만든 뒤
callback authorization code를 `/platform/v1/auth/social/exchanges`로 교환한다. 기본 `getAccessToken()`은 Modo backend
bootstrap용 Auth session access token을 반환한다. `getAccessToken(SpectraGetAccessTokenOptions(service: .storage/.chat/.notification))`
같은 service token은 StorageSDK·ChatSDK·NotificationSDK 내부 요청용이며 앱 backend bootstrap bearer로 쓰지 않는다.

`PublicAppUserSessionStrategy`는 Auth Platform의 public app-user session API를 호출한다. 이번 slice에서
지원하는 provider는 non-production `dev_mock`이며, 최초 session 생성은
`POST /v1/app-user-sessions/dev-provider`, 이후 refresh/logout은 각각
`POST /v1/app-user-sessions/refresh`, `POST /v1/app-user-sessions/logout`을 사용한다.

`AppUserAccessTokenRefreshStrategy`와 `AppUserRefreshSessionStrategy`는 internal/dev bridge 확인용으로 유지한다.
운영 앱 bundle에는 internal key를 넣지 않는다.

## 설치

Xcode에서 `File > Add Package Dependencies...`를 열고 아래 Git URL을 추가한다.

```text
https://github.com/Spectra-Platform/auth-sdk-ios.git
```

개발 중에는 `main` branch를 사용할 수 있다.

```swift
.package(
    url: "https://github.com/Spectra-Platform/auth-sdk-ios.git",
    branch: "main"
)
```

버전 태그가 발행된 뒤에는 앱에서 SemVer 범위를 고정한다.

```swift
.package(
    url: "https://github.com/Spectra-Platform/auth-sdk-ios.git",
    .upToNextMinor(from: "0.1.0")
)
```

target dependency에는 product 이름을 사용한다.

```swift
.product(name: "SpectraAuthSDK", package: "auth-sdk-ios")
```

릴리즈 전 확인 절차는 [release checklist](docs/guides/release-checklist.md)를 따른다. 현재 저장소는 SwiftPM Git package로 소비 가능하도록 준비하며, 최초 SemVer tag는 공개 버전 번호를 확정한 뒤 별도로 생성한다.

## 사용 예시

자세한 앱 통합 흐름은 [iOS AuthSDK integration guide](docs/guides/ios-auth-sdk-integration.md)를 기준으로 본다.
Modo Camp의 JS SDK parity 목표와 Auth callback 설정은
[Modo Camp iOS Auth SDK parity guide](docs/guides/modo-camp-ios-auth-parity.md)에
별도로 정리한다.

```swift
import Foundation
import SpectraAuthSDK

let auth = SpectraAuthClient(
    configuration: .live(
        projectId: "project_123",
        publicClientId: "public_client_123",
        redirectURI: URL(string: "modocamp://spectra-auth/callback")
    ),
    sessionStore: KeychainAuthSessionCache(
        account: "project_123:auth"
    )
)

let session = try await auth.signInWithGoogle()
let bootstrapToken = try await auth.getAccessToken()

var request = URLRequest(url: URL(string: "https://api.modocamp.example/v1/me/bootstrap")!)
request.setValue("Bearer \(bootstrapToken.value)", forHTTPHeaderField: "Authorization")
```

로컬 또는 staging QA에서는 `.custom(...)`으로 test Auth base URL과 callback URI를 넘긴다.

```swift
let testAuth = SpectraAuthClient(
    configuration: .custom(
        baseURL: URL(string: "http://127.0.0.1:8081")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .test,
        redirectURI: URL(string: "modocamp-dev://spectra-auth/callback")
    ),
    sessionStore: KeychainAuthSessionCache(account: "project_123:test-auth")
)
```

기존 `dev_mock` public session 전략은 non-production SDK 연동 검증용으로 남아 있다.

```swift
let cachedPublicDevAuth = try await AuthClient.restoringCachedSession(
    configuration: .local(
        projectId: "project_123",
        publicClientId: "public_client_123"
    ),
    refreshStrategy: PublicAppUserSessionStrategy(
        service: .chat,
        sessionProvider: DevMockAppUserSessionProvider(
            providerSubject: "dev-user-1"
        )
    ),
    sessionCache: KeychainAuthSessionCache(account: "project_123:dev-user-1")
)

let publicDevAuth = AuthClient(
    configuration: .custom(
        baseURL: URL(string: "https://auth.example.com")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .test
    ),
    refreshStrategy: PublicAppUserSessionStrategy(
        service: .storage,
        sessionProvider: DevMockAppUserSessionProvider(
            providerSubject: "dev-user-1"
        )
    ),
    sessionCache: KeychainAuthSessionCache(
        account: "project_123:dev-user-1"
    )
)

struct StorageClient {
    let tokenProvider: any TokenProvider

    func makeRequest(url: URL) async throws -> URLRequest {
        try await tokenProvider.authorizedRequest(URLRequest(url: url))
    }
}

let storage = StorageClient(tokenProvider: publicDevAuth)
```

개별 SDK 패키지 내부에서 특정 기능 token이 필요한 경우에만 `ServiceTokenProvider` helper를 사용한다. 앱 개발자가
직접 내부 대상 값이나 exchange 값을 조립하는 방식으로 안내하지 않는다.

```swift
let notificationToken = try await publicDevAuth.getAccessToken(for: .notification)
let chatRequest = try await publicDevAuth.authorizedRequest(
    URLRequest(url: URL(string: "https://chat.spectra.kr/v1/socket-token")!),
    for: .chat
)
```

`dev_mock` provider는 Auth Platform non-production runtime에서만 허용된다. `PublicAppUserSessionStrategy`는
service별 access token을 요청하고 refresh token rotation이 발생하면 같은 `AuthClient` 안의 다른 service cache에도
새 refresh token을 전파한다.

`additionalHeaders`를 받는 internal/dev strategy의 internal key는 local bridge 확인용이다. 운영 앱 bundle에는
내부 key나 Project API token을 넣지 않는다.

모바일 앱 bundle에는 Project API token, provider client secret, Apple private key 같은 secret을 넣지 않는다. 앱은 AuthSDK를 통해 project/app-user context에 맞는 access token을 얻고, 다른 SDK는 `TokenProvider`만 의존한다.

`KeychainAuthSessionCache`는 iOS/macOS의 Security framework가 있는 환경에서 session JSON만 저장한다. refresh token도
session payload 안에 포함되므로 앱은 `account` 값을 project/user 단위로 안정적으로 지정하고, 로그에는 access token,
refresh token 또는 cache payload를 출력하지 않는다.

## 로컬 검증

```bash
swift package describe
swift test
```

## 현재 미완료 경계

- Universal Link-only hosted login helper와 callback URL 생성 API
- 실제 Google/Apple provider, Modo Camp iOS 앱, 실기기 E2E 검증
- server SDK/helper와 공개 JWKS/introspection 정책 고정
