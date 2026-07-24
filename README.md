# Spectra AuthSDK for iOS

Swift Package 기반의 Spectra Platform iOS Auth SDK다. 이 저장소의 첫 구현 slice는 앱이 공개 가능한 Project/App Client 설정으로 `AuthClient`를 만들고, StorageSDK·NotificationSDK 같은 다른 SDK가 `TokenProvider`를 주입받아 사용자 bearer token을 요청에 붙일 수 있는 최소 경계를 제공한다.

## 현재 구현 상태

- Swift Package: `SpectraAuthSDK`
- Public configuration: `baseURL`, `projectId`, `publicClientId`, `environment`, `redirectURI`
- Public token provider: `TokenProvider`, `AuthClient`, `AccessToken`, `AuthSession`, `AppUser`
- Request helper: `authorizationHeader(forceRefresh:)`, `authorizedRequest(_:forceRefresh:)`
- Refresh boundary: `AuthTokenRefreshStrategy`
- 검증: `swift test`

이번 slice는 실제 소셜 로그인, Apple/Google provider 연동, Keychain 영구 저장, refresh token rotation, 운영 배포를 구현하지 않는다. 해당 기능은 Auth Platform Identity Plane의 app-user session API가 producer로 구현된 뒤 붙인다.

## 사용 예시

자세한 앱 통합 흐름은 [iOS AuthSDK integration guide](docs/guides/ios-auth-sdk-integration.md)를 기준으로 본다.

```swift
import Foundation
import SpectraAuthSDK

let auth = AuthClient(
    configuration: AuthClientConfiguration(
        baseURL: URL(string: "https://auth.example.com")!,
        projectId: "project_123",
        publicClientId: "public_client_123",
        environment: .test,
        redirectURI: URL(string: "spectra-example://auth/callback")
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

모바일 앱 bundle에는 Project API token, provider client secret, Apple private key 같은 secret을 넣지 않는다. 앱은 AuthSDK를 통해 project/app-user context에 맞는 access token을 얻고, 다른 SDK는 `TokenProvider`만 의존한다.

## 로컬 검증

```bash
swift test
```

## 현재 미완료 경계

- Apple/Google native sign-in entrypoint
- Auth Platform social exchange API 연동
- Keychain refresh session 저장
- refresh token rotation/reuse detection/logout revocation
- 실제 Spectra iOS 앱 integration과 실기기 E2E
