# 2026-07-28 — Public dev/mock app-user session strategy

## 작업 목적과 이해한 내용

Auth Platform 서버가 public SDK-facing app-user session API를 열었으므로 iOS AuthSDK도 internal key bridge가 아니라 공개 가능한 Project/App Client 설정만으로 session create/refresh/logout을 소비해야 한다. 이번 범위는 Apple/Google real exchange가 아니라 non-production `dev_mock` provider를 통한 production-shaped SDK 흐름이다.

## 기존 동작

- `AppUserAccessTokenRefreshStrategy`는 `/internal/dev/v1/app-user-access-tokens`를 호출해 단발 access token만 받았다.
- `AppUserRefreshSessionStrategy`는 `/internal/dev/v1/app-user-sessions`, `/refresh`, `/logout`을 호출하지만 `X-Spectra-Internal-Key` 추가가 필요한 local/dev bridge였다.
- `AuthClient`는 service별 session을 cache했지만, 한 service refresh로 refresh token이 회전될 때 같은 refresh session을 공유하던 다른 service cache까지 새 refresh token을 전파하지 않았다.

## 적용 내용과 주요 변경 파일

- `Sources/SpectraAuthSDK/PublicAppUserSessionStrategy.swift`
  - `AppUserSessionProvider` protocol을 추가해 최초 provider exchange 경계를 추상화했다.
  - `DevMockAppUserSessionProvider`를 추가했다.
    - `POST /v1/app-user-sessions/dev-provider` 호출
    - body: `project_id`, `public_client_id`, `environment`, `provider=dev_mock`, `provider_subject`, `service`
    - `.live` configuration에서는 네트워크 호출 전 fail-closed
  - `PublicAppUserSessionStrategy`를 추가했다.
    - refresh: `POST /v1/app-user-sessions/refresh`
    - logout: `POST /v1/app-user-sessions/logout`
    - internal header를 사용하지 않음
- `Sources/SpectraAuthSDK/AppUserSessionHTTP.swift`
  - app-user session endpoint URL 구성, JSON header 설정, RFC3339 date decode와 session response 검증을 공통 helper로 분리했다.
- `Sources/SpectraAuthSDK/AppUserRefreshSessionStrategy.swift`
  - 기존 internal/dev session strategy의 동작은 유지하면서 공통 helper를 재사용하게 정리했다.
- `Sources/SpectraAuthSDK/AuthClient.swift`
  - service별 token 요청 중 refresh token rotation이 발생하면 같은 refresh session을 공유하던 다른 service cache에도 새 refresh token을 전파하게 했다.
  - service별 access token은 계속 각각의 audience cache로 보관한다.
- `Tests/SpectraAuthSDKTests/AuthClientTests.swift`
  - public create → service-scoped refresh → refresh rotation propagation → logout local clear/request body를 검증했다.
  - `dev_mock` provider가 `.live` configuration에서 네트워크 호출 전 거부되는지 검증했다.
- `README.md`, `HANDOFF.md`, `WORKLOG.md`, `docs/guides/ios-auth-sdk-integration.md`, `docs/guides/release-checklist.md`
  - public dev/mock 구현 상태와 Apple/Google real exchange 미완료 상태를 정리했다.

## 검증과 결과

- `swift test` 통과
  - 18 tests
- `git diff --check` 통과

## 남은 작업과 주의사항

- Apple/Google real provider exchange SDK entrypoint는 아직 구현하지 않았다.
- Spectra 앱에는 아직 적용하지 않았다.
- SwiftPM SemVer tag/version bump는 아직 하지 않았다.
- public contract 게시와 generated contract sync는 후속 작업이다.

## 커밋 기록

- `767cfd86b9c9da2a971f1b2fa47d0b5da6894720` — `feat: add public dev app-user sessions`
  - public dev/mock session strategy, 공통 session HTTP helper, service refresh token rotation 전파, 테스트와 README 갱신
