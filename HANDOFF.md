# HANDOFF

## 목적과 소유 범위

`auth-sdk-ios`는 Spectra Platform Auth의 iOS 공개 SDK를 소유한다. 앱이 공개 가능한 Project/App Client 설정으로 Auth 클라이언트를 만들고, StorageSDK·NotificationSDK 같은 다른 SDK에 app-user token provider를 주입하는 경계를 제공한다.

이 저장소는 iOS SDK만 소유한다. Auth API producer, Identity Plane DB, provider secret 저장, Storage/Notification 서버 검증과 운영 배포는 각각 해당 플랫폼 저장소의 소유 범위다.

## 확정된 결정

- iOS 앱 bundle에는 Project API token, provider client secret, Apple private key, Console session cookie를 넣지 않는다.
- SDK configuration에는 공개 가능한 `baseURL`, `projectId`, `publicClientId`, `environment`, `redirectURI`만 둔다.
- `AuthClient`는 `TokenProvider`를 구현하며 다른 SDK는 concrete AuthSDK가 아니라 `TokenProvider` protocol을 주입받는다.
- 요청별 Authorization 부착은 `TokenProvider.authorizedRequest(_:forceRefresh:)` 또는 `authorizationHeader(forceRefresh:)`를 사용한다.
- access token cache/expiry와 refresh는 `AuthClient` actor 내부와 `AuthTokenRefreshStrategy` 경계에 둔다.
- 기본 refresh 구현은 의도적으로 `AuthError.refreshUnavailable`로 닫는다. 추가로
  `AppUserAccessTokenRefreshStrategy`가 Auth Platform internal/dev app-user token endpoint를 호출해
  `storage`·`email`·`notification` 단일 service token을 받아오는 최소 HTTP surface를 제공한다.
  이 strategy는 local/dev bridge용이며 공개 hosted social session, refresh token rotation과 logout
  revocation은 아직 구현하지 않았다.
- Swift Package Manager 배포는 Git URL 기반으로 시작한다. repository URL은 `https://github.com/Spectra-Platform/auth-sdk-ios.git`, product 이름은 `SpectraAuthSDK`다.
- release tag는 `vMAJOR.MINOR.PATCH` 형식으로 만들며, 최초 tag는 공개 버전 번호를 확정한 뒤 생성한다. 현재 문서와 CI는 tag 배포가 가능한 상태를 준비하지만 tag 자체는 만들지 않는다.

## 현재 구현 경계

- Swift Package `SpectraAuthSDK`가 생성됐다.
- `.github/workflows/ci.yml`이 SwiftPM resolve/describe/test를 검증한다.
- Public surface:
  - `AuthClientConfiguration`
  - `AuthEnvironment`
  - `TokenProvider`
  - `AuthClient`
  - `AccessToken`
  - `AuthSession`
  - `AppUser`
  - `AuthTokenRefreshStrategy`
  - `AuthError`
- `AuthClient`는 actor이며 만료되지 않은 in-memory access token은 그대로 반환하고, 만료됐거나 `forceRefresh`면 주입된 refresh strategy를 호출한다.
- `AppUserAccessTokenRefreshStrategy`는 Auth Platform `POST /internal/dev/v1/app-user-access-tokens`를
  호출하고, 응답의 project/environment/app_user/audience가 요청 service와 일치할 때만 `AuthSession`을
  갱신한다.
- unit test는 cache hit, 만료 refresh, bearer request helper, logout 후 상태 삭제를 검증한다.
- iOS 앱 통합 기준 문서는 `docs/guides/ios-auth-sdk-integration.md`에 둔다.
- SwiftPM 릴리즈 기준은 `docs/guides/release-checklist.md`에 둔다.

## 변경 시 함께 확인할 계약·저장소

- `Spectra-Platform/auth-platform`: Identity Plane, app-user access/refresh session producer, JWKS 또는 introspection 결정
- `Spectra-Platform/storage-platform`: app-user token 검증과 user-root object scope
- `Spectra-Platform/delivery-platform` 또는 Notification/Push 관련 저장소: device registration과 user-scoped preference token 검증
- `spectra-contracts`: Auth public contract의 app session, social challenge/exchange, refresh/logout, JWKS operation

## 남은 작업과 미확정 항목

- Apple/Google native sign-in entrypoint와 Auth social exchange API 연결
- Keychain 기반 refresh token/session 저장
- refresh token rotation, reuse detection, logout revocation 연결
- access token이 JWT인지 opaque token + introspection인지 최종 확정
- token TTL, refresh rotation grace, signing key/JWKS overlap
- 실제 iOS 앱·실기기 E2E와 운영 배포

## 마지막으로 코드와 대조한 날짜

- 2026-07-24
