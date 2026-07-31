# 2026-07-27 — App-user refresh session strategy

## 작업 목적과 이해한 내용

Auth Platform에 internal/dev app-user refresh session producer가 추가됐으므로 iOS AuthSDK도 단발 access token 발급에 머물지 않고 refresh token 기반 session 생성, 회전과 logout revoke를 사용할 수 있어야 한다.

다른 SDK는 계속 `TokenProvider` 또는 `ServiceTokenProvider`만 의존해야 하며, AuthSDK 내부에서 service별 access token cache와 refresh session 처리를 담당한다.

## 문제 진단 또는 기존 동작

- `AppUserAccessTokenRefreshStrategy`는 `/internal/dev/v1/app-user-access-tokens`로 매번 단발 access token만 발급받았다.
- `AuthSession`에는 refresh token 정보가 없어 access token 만료 후 장기 session 회전이나 서버 logout revoke를 표현할 수 없었다.
- `AuthClient.logout()`은 local memory/cache만 지우고 서버 session revoke는 호출하지 않았다.

## 적용한 내용과 주요 변경 파일

- `Sources/SpectraAuthSDK/AuthSession.swift`
  - `AppUserRefreshToken`을 추가했다.
  - `AuthSession`에 optional `refreshToken`을 추가해 기존 session과 호환되게 했다.
- `Sources/SpectraAuthSDK/AuthTokenRefreshStrategy.swift`
  - logout 시 서버 session revoke를 선택적으로 지원하는 `AuthSessionRevocationStrategy`를 추가했다.
- `Sources/SpectraAuthSDK/AuthClient.swift`
  - `logout()`에서 refresh strategy가 revocation을 지원하면 service별 refresh session을 중복 없이 revoke한 뒤 local/cache를 지우게 했다.
- `Sources/SpectraAuthSDK/AppUserRefreshSessionStrategy.swift`
  - 최초 token 요청 시 `/internal/dev/v1/app-user-sessions`를 호출한다.
  - 기존 session에 유효한 refresh token이 있으면 `/internal/dev/v1/app-user-sessions/refresh`를 호출해 refresh token을 회전한다.
  - logout 시 `/internal/dev/v1/app-user-sessions/logout`을 호출한다.
  - 응답의 project, public client, environment, app user, audience를 fail-closed로 검증한다.
- `Tests/SpectraAuthSDKTests/AuthClientTests.swift`
  - create → refresh rotation → logout revoke 요청 path/header/body와 cache 갱신·삭제를 검증하는 회귀 테스트를 추가했다.
- `README.md`, `HANDOFF.md`, `WORKLOG.md`
  - refresh session strategy의 실제 구현 상태와 남은 hosted/social 경계를 반영했다.

## 실행한 검증과 결과

- `swift test` — 16 tests 통과
- `git diff --check` — 통과

## 남은 작업, 미검증 항목 또는 주의사항

- 이 strategy는 아직 internal/dev bridge용이다.
- Apple/Google native sign-in entrypoint와 공개 hosted social exchange API 연결은 남아 있다.
- access token의 최종 운영 검증 방식(JWT/JWKS 또는 opaque introspection)은 아직 확정되지 않았다.
- Spectra iOS 앱에 새 strategy를 적용한 실기기 E2E는 이번 저장소 작업 범위 밖이다.

## 커밋 기록

- 구현 커밋: `29ddd07 feat: add app-user refresh session strategy`
