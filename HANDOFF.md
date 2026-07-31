# HANDOFF

## 목적과 소유 범위

`auth-sdk-ios`는 Spectra Platform Auth의 iOS 공개 SDK를 소유한다. 앱이 공개 가능한 Project/App Client 설정으로 Auth 클라이언트를 만들고, StorageSDK·NotificationSDK 같은 다른 SDK에 app-user token provider를 주입하는 경계를 제공한다.

이 저장소는 iOS SDK만 소유한다. Auth API producer, Identity Plane DB, provider secret 저장, Storage/Notification 서버 검증과 운영 배포는 각각 해당 플랫폼 저장소의 소유 범위다.

## 확정된 결정

- iOS 앱 bundle에는 Project API token, provider client secret, Apple private key, Console session cookie를 넣지 않는다.
- SDK configuration에는 공개 가능한 `baseURL`, `projectId`, `publicClientId`, `environment`, `redirectURI`만 둔다.
- Core SDK는 Auth SDK보다 먼저 만들지 않는다. Auth/Notification/Storage/Chat/Call 같은 개별 SDK가 먼저
  public API와 검증 경계를 갖고, 이후 Core SDK는 이 개별 SDK들을 조합하는 통합 설정·session·transport
  진입점으로 설계한다.
- `AuthClient`는 `TokenProvider`와 `ServiceTokenProvider`를 구현한다. 다른 SDK는 concrete AuthSDK가 아니라
  service-aware token provider protocol을 주입받는다. 단, 앱-facing 문서와 예시는 service audience나 내부
  token exchange를 먼저 설명하지 않고, 로그인과 개별 SDK 사용 흐름을 먼저 보여준다.
- 요청별 Authorization 부착은 `TokenProvider.authorizedRequest(_:forceRefresh:)` 또는 `authorizationHeader(forceRefresh:)`를 사용한다.
- service별 Authorization 부착은 `ServiceTokenProvider.authorizedRequest(_:for:forceRefresh:)` 또는
  `authorizationHeader(for:forceRefresh:)`를 사용한다.
- access token cache/expiry와 refresh는 `AuthClient` actor 내부와 `AuthTokenRefreshStrategy` 경계에 둔다.
  refresh token rotation이 발생하면 같은 refresh session을 공유하던 service별 cached session에도 새 refresh token을
  전파해 다음 service refresh가 이미 회전된 token을 재사용하지 않게 한다.
- Storage·Email·Notification·Chat·Call은 같은 Auth 객체를 공유하되 service별 access token을 별도로
  요청·cache·refresh한다. legacy `TokenProvider` API는 `defaultService`로 동작해 기존 SDK 소비자 호환을 유지한다.
- session cache는 `AuthSessionCache` protocol로 추상화한다. SDK 기본 편의 구현은 `InMemoryAuthSessionCache`와
  iOS/macOS Security framework 기반 `KeychainAuthSessionCache`이며, 둘 다 service별 session cache를 지원한다.
  cache payload나 access token은 로그에 출력하지 않는다.
- environment setup은 기존 initializer를 유지하되 `AuthClientConfiguration.live(...)`, `.local(...)`,
  `.custom(...)` factory를 함께 제공한다. local factory는 현재 dev bridge의 `test` environment를 사용한다.
- 기본 refresh 구현은 의도적으로 `AuthError.refreshUnavailable`로 닫는다.
- 공개 SDK-facing session strategy는 `PublicAppUserSessionStrategy`가 소유한다. 최초 session 생성은
  `AppUserSessionProvider` protocol로 추상화하고, 이번 slice의 provider 구현은 non-production
  `DevMockAppUserSessionProvider`다. 이 provider는 `POST /v1/app-user-sessions/dev-provider`를 호출하며
  `.live` configuration에서는 네트워크 호출 전 fail-closed 한다.
- public session refresh/logout은 internal key 없이 `POST /v1/app-user-sessions/refresh`와
  `POST /v1/app-user-sessions/logout`을 호출한다. refresh token 원문은 `AuthSession`과 사용자 제공 cache 경계 안에만
  저장하고 로그에는 남기지 않는다.
- internal/dev bridge는 별도 strategy로 유지한다. `AppUserAccessTokenRefreshStrategy`가 Auth Platform internal/dev app-user token endpoint를 호출해
  `storage`·`email`·`notification`·`chat`·`call` 단일 service token을 받아오는 최소 HTTP surface를 제공한다.
  이 strategy는 local/dev 단발 access token bridge용이다.
- `AppUserRefreshSessionStrategy`는 Auth Platform internal/dev app-user session endpoint를 호출해 최초
  refresh session 생성, refresh token 1회성 회전, logout revoke를 처리한다. 이 strategy도 local/dev bridge용이며
  public dev/mock strategy와 Apple/Google provider exchange와는 별도다.
- Swift Package Manager 배포는 Git URL 기반으로 시작한다. repository URL은 `https://github.com/Spectra-Platform/auth-sdk-ios.git`, product 이름은 `SpectraAuthSDK`다.
- release tag는 `vMAJOR.MINOR.PATCH` 형식으로 만들며, 최초 tag는 공개 버전 번호를 확정한 뒤 생성한다. 현재 문서와 CI는 tag 배포가 가능한 상태를 준비하지만 tag 자체는 만들지 않는다.

## 현재 구현 경계

- Swift Package `SpectraAuthSDK`가 생성됐다.
- `.github/workflows/ci.yml`이 SwiftPM resolve/describe/test를 검증한다.
- Public surface:
  - `AuthClientConfiguration`
  - `AuthEnvironment`
  - `TokenProvider`
  - `ServiceTokenProvider`
  - `AuthClient`
  - `AccessToken`
  - `AuthSession`
  - `AppUserRefreshToken`
  - `AppUser`
  - `AuthTokenRefreshStrategy`
  - `ServiceScopedAuthTokenRefreshStrategy`
  - `ServiceAwareAuthTokenRefreshStrategy`
  - `AuthSessionRevocationStrategy`
  - `PublicAppUserSessionStrategy`
  - `AppUserSessionProvider`
  - `DevMockAppUserSessionProvider`
  - `AuthSessionCache`
  - `ServiceAuthSessionCache`
  - `InMemoryAuthSessionCache`
  - `KeychainAuthSessionCache`
  - `AuthError`
- `AuthClient`는 actor이며 만료되지 않은 in-memory access token은 service별로 그대로 반환하고,
  만료됐거나 `forceRefresh`면 주입된 refresh strategy를 호출한다.
- `AuthClient.restoringCachedSession(...)`와 `restoreSessionFromCache()`로 cache에서 session을 복구할 수
  있고, refresh 성공 시 cache에 갱신 session을 저장한다. `initialSession`을 주입한 기존 동작은 유지한다.
- `PublicAppUserSessionStrategy`는 provider abstraction을 통해 최초 session을 만들고, `DevMockAppUserSessionProvider`는
  Auth Platform `POST /v1/app-user-sessions/dev-provider`로 `project_id`, `public_client_id`, `environment`,
  `provider=dev_mock`, `provider_subject`, `service`를 보낸다. access token은 서버가 발급한 service audience JWT로
  취급하며 SDK는 응답의 project/client/environment/audience/scope를 검증한다.
- public refresh/logout은 각각 `POST /v1/app-user-sessions/refresh`, `POST /v1/app-user-sessions/logout`을
  호출한다. refresh 응답으로 refresh token이 회전되면 `AuthClient`가 같은 refresh session을 공유하던 service별 cache에도
  새 refresh token을 반영한다.
- `AppUserAccessTokenRefreshStrategy`는 Auth Platform `POST /internal/dev/v1/app-user-access-tokens`를
  호출하고, 응답의 project/environment/app_user/audience가 요청 service와 일치할 때만 `AuthSession`을
  갱신한다. service-aware refresh 요청을 받으면 해당 service로 body를 구성한다.
- `AppUserRefreshSessionStrategy`는 Auth Platform `POST /internal/dev/v1/app-user-sessions`로 최초 refresh
  session과 access token을 받고, 이후 `POST /internal/dev/v1/app-user-sessions/refresh`로 refresh token을
  회전한다. `AuthClient.logout()`은 strategy가 `AuthSessionRevocationStrategy`를 구현하면
  `/internal/dev/v1/app-user-sessions/logout`을 호출한 뒤 local/session cache를 지운다.
- unit test는 cache hit, 만료 refresh, bearer request helper, logout 후 상태 삭제, service expansion,
  configuration preset/validation, cache restore/store, service별 token cache, service별 force refresh와
  audience mismatch 차단, public/internal refresh session 생성·회전·logout request body와 `dev_mock` live fail-closed를
  검증한다.
- iOS 앱 통합 기준 문서는 `docs/guides/ios-auth-sdk-integration.md`에 둔다.
- SwiftPM 릴리즈 기준은 `docs/guides/release-checklist.md`에 둔다.

## 변경 시 함께 확인할 계약·저장소

- `Spectra-Platform/auth-platform`: Identity Plane, app-user access/refresh session producer, JWKS 또는 introspection 결정
- `Spectra-Platform/storage-platform`: app-user token 검증과 user-root object scope
- `Spectra-Platform/delivery-platform` 또는 Notification/Push 관련 저장소: device registration과 user-scoped preference token 검증
- `spectra-contracts`: Auth public contract의 app session, social challenge/exchange, refresh/logout, JWKS operation

## 남은 작업과 미확정 항목

- Apple/Google native sign-in entrypoint와 Auth social exchange API 연결
- Apple/Google real provider exchange SDK entrypoint와 서버 API 연결
- app-facing API에서 `ServiceTokenProvider`/`AuthService`를 직접 다루지 않아도 되는 convenience 또는 future Core SDK
  composition 경계
- public client/provider config registration, bundle/team/redirect 검증 반영
- token TTL, refresh rotation grace, signing key/JWKS overlap
- 실제 iOS 앱·실기기 E2E와 운영 배포
- 후속 Spectra 앱/시뮬레이터 검증은 Google 로그인 세션이 아니라 사용자가 지정한 테스트유저 1/테스트유저 2와
  각 계정의 초기화 기능을 사용해 반복 가능하게 수행한다.

## 마지막으로 코드와 대조한 날짜

- 2026-07-31
