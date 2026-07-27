# Spectra AuthSDK for iOS

Swift Package 기반의 Spectra Platform iOS Auth SDK다. 이 저장소의 첫 구현 slice는 앱이 공개 가능한 Project/App Client 설정으로 `AuthClient`를 만들고, StorageSDK·NotificationSDK 같은 다른 SDK가 `TokenProvider`를 주입받아 사용자 bearer token을 요청에 붙일 수 있는 최소 경계를 제공한다.

## 현재 구현 상태

- Swift Package: `SpectraAuthSDK`
- Package URL: `https://github.com/Spectra-Platform/auth-sdk-ios.git`
- Public configuration: `baseURL`, `projectId`, `publicClientId`, `environment`, `redirectURI`
- Public token provider: `TokenProvider`, `AuthClient`, `AccessToken`, `AuthSession`, `AppUser`
- Request helper: `authorizationHeader(forceRefresh:)`, `authorizedRequest(_:forceRefresh:)`
- Refresh boundary: `AuthTokenRefreshStrategy`, `AppUserAccessTokenRefreshStrategy`
- Environment helpers: `AuthClientConfiguration.live(...)`, `.local(...)`, `.custom(...)`
- Session cache boundary: `AuthSessionCache`, `InMemoryAuthSessionCache`, `KeychainAuthSessionCache`
- 검증: `swift test`

`AppUserAccessTokenRefreshStrategy`는 현재 Auth Platform의 internal/dev app-user token bridge를 호출한다.
실제 소셜 로그인, Apple/Google provider 연동, refresh token rotation, 운영 배포는 아직
구현하지 않는다. 해당 기능은 Auth Platform Identity Plane의 hosted/social app-user session API가
producer로 구현된 뒤 붙인다.

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

```swift
import Foundation
import SpectraAuthSDK

let auth = AuthClient(
    configuration: .local(
        projectId: "project_123",
        publicClientId: "public_client_123",
        redirectURI: URL(string: "spectra-example://auth/callback")
    )
)

let cachedAuth = try await AuthClient.restoringCachedSession(
    configuration: .live(
        projectId: "project_123",
        publicClientId: "public_client_123"
    ),
    refreshStrategy: AppUserAccessTokenRefreshStrategy(
        service: .chat,
        appUserIdProvider: { "app_user_123" }
    ),
    sessionCache: KeychainAuthSessionCache(account: "project_123:app_user_123")
)

let localEmailAuth = AuthClient(
    configuration: .custom(
        baseURL: URL(string: "https://auth.example.com")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .test
    ),
    refreshStrategy: AppUserAccessTokenRefreshStrategy(
        service: .email,
        additionalHeaders: ["X-Spectra-Internal-Key": "local-dev-only"],
        appUserIdProvider: { "app_user_123" }
    )
)

struct StorageClient {
    let tokenProvider: any TokenProvider

    func makeRequest(url: URL) async throws -> URLRequest {
        try await tokenProvider.authorizedRequest(URLRequest(url: url))
    }
}

let storage = StorageClient(tokenProvider: auth)
```

`additionalHeaders`의 internal key는 local/dev bridge 확인용이다. 운영 앱 bundle에는 내부 key나 Project API
token을 넣지 않는다.

모바일 앱 bundle에는 Project API token, provider client secret, Apple private key 같은 secret을 넣지 않는다. 앱은 AuthSDK를 통해 project/app-user context에 맞는 access token을 얻고, 다른 SDK는 `TokenProvider`만 의존한다.

`KeychainAuthSessionCache`는 iOS/macOS의 Security framework가 있는 환경에서 session JSON만 저장한다. 앱은
`account` 값을 project/user 단위로 안정적으로 지정하고, 로그에는 access token 또는 cache payload를 출력하지 않는다.

## 로컬 검증

```bash
swift package describe
swift test
```

## 현재 미완료 경계

- Apple/Google native sign-in entrypoint
- Auth Platform social exchange API 연동
- 운영용 app-user access/refresh session API
- refresh token rotation/reuse detection/logout revocation
- 실제 Spectra iOS 앱 integration과 실기기 E2E
