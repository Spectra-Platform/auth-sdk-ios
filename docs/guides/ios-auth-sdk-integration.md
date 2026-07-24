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
    baseURL: URL(string: "https://console.spectra.kr")!,
    projectId: "project_xxx",
    publicClientId: "public_client_xxx",
    environment: .test,
    redirectURI: URL(string: "spectra-example://auth/callback")
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

현재 SDK는 token provider 경계를 먼저 제공한다. 실제 Apple/Google sign-in과 hosted exchange는 아직 구현되지 않았다.

```swift
let authClient = AuthClient(configuration: configuration)
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

## 4. Access token 조회

```swift
let token = try await authClient.getAccessToken()
print(token.value)
```

강제 refresh:

```swift
let refreshed = try await authClient.getAccessToken(forceRefresh: true)
```

현재 기본 refresh strategy는 `AuthError.refreshUnavailable`을 반환한다. 실제 refresh/session rotation은 Auth Platform Identity Plane의 app-user session API가 구현된 뒤 연결한다.

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
await authClient.logout()
```

현재 logout은 in-memory session을 지운다. 운영 logout revocation은 Auth Platform refresh/session API 연결 후 완료된다.

## 현재 완료 상태

- Swift Package build/test
- `AuthClient`
- `TokenProvider`
- access token cache/expiry 경계
- authorized request helper
- logout local state clear

## 아직 완료가 아닌 것

- Apple/Google native sign-in
- Auth social exchange API
- Keychain refresh session 저장
- refresh token rotation/reuse detection
- logout server revocation
- 실제 Spectra iOS app integration

