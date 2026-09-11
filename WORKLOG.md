# WORKLOG

## 2026-09-11 — Modo Camp Auth parity draft

- 상태: 문서 계약 초안 완료, production Google/Apple login 구현은 미완료
- 목적: Modo Camp iOS가 React 웹 Auth SDK와 같은 의미의 Auth access token, session store,
  callback/deep link, logout 경계를 사용할 수 있도록 Swift public API 목표를 고정한다.
- 결과: `docs/guides/modo-camp-ios-auth-parity.md`에 Modo production 설정, API 초안,
  ASWebAuthenticationSession/Universal Link callback 가이드, redaction 규칙과 JS parity checklist를 추가했다.
- 검증: 문서 변경만 수행했다. Swift code는 변경하지 않았다.
- 상세 기록: [`docs/work-logs/2026-09-11-01-modo-camp-auth-parity.md`](docs/work-logs/2026-09-11-01-modo-camp-auth-parity.md)

## 2026-07-31 — SDK public surface alignment

- 상태: 문서 보정 완료, 코드 public API는 호환성 유지를 위해 유지
- 목적: AuthSDK 문서가 service audience/internal token exchange 중심으로 보이지 않게 하고, 개별 SDK 우선 제작 후 future Core SDK가 조합한다는 방향을 고정한다.
- 결과: README와 HANDOFF에 Core SDK는 Auth/Notification/Storage/Chat/Call 개별 SDK가 안정된 뒤 통합 설정·session·transport 진입점으로 설계한다는 결정을 추가했다. `ServiceTokenProvider`는 앱 화면 코드가 직접 다루는 개념이 아니라 개별 SDK 패키지 내부의 low-level 기능 token 경계로 설명을 바꿨다.
- 검증: `swift test` 18 tests 통과, `git diff --check` 통과.
- 상세 기록: [`docs/work-logs/2026-07-31-01-sdk-public-surface-alignment.md`](docs/work-logs/2026-07-31-01-sdk-public-surface-alignment.md)

## 2026-07-28 — Public dev/mock app-user session strategy

- 상태: Swift Package 구현·검증 완료, Apple/Google real provider exchange와 Spectra 앱 적용은 미구현
- 목적: Auth Platform의 public `dev_mock` app-user session API를 iOS AuthSDK에서 소비해, internal key 없이 public SDK-facing create/refresh/logout 흐름을 검증 가능하게 한다.
- 결과: `PublicAppUserSessionStrategy`, `AppUserSessionProvider`, `DevMockAppUserSessionProvider`를 추가했다. 최초 session 생성은 `/v1/app-user-sessions/dev-provider`, refresh/logout은 `/v1/app-user-sessions/refresh`, `/v1/app-user-sessions/logout`을 호출한다. service별 token 요청 중 refresh token rotation이 발생하면 같은 refresh session을 공유하던 다른 service cache에도 새 refresh token을 전파한다.
- 검증: `swift test` 18 tests 통과, `git diff --check` 통과
- 상세 기록: [`docs/work-logs/2026-07-28-01-public-dev-app-user-session-strategy.md`](docs/work-logs/2026-07-28-01-public-dev-app-user-session-strategy.md)

## 2026-07-27 — App-user refresh session strategy

- 상태: Swift Package 구현·검증 완료, 공개 hosted social session과 실기기 E2E는 미구현
- 목적: Auth Platform의 internal/dev app-user refresh session API를 iOS AuthSDK에서 사용해 service token을 장기 session 기반으로 발급·회전·해지할 수 있게 한다.
- 결과: `AuthSession`에 optional `AppUserRefreshToken`을 추가하고 `AppUserRefreshSessionStrategy`를 구현했다. 최초 요청은 `/internal/dev/v1/app-user-sessions`, 이후 refresh는 `/refresh`, `AuthClient.logout()`은 strategy가 revoke를 지원하면 `/logout`을 호출한다.
- 검증: `swift test` 16 tests 통과, `git diff --check` 통과
- 상세 기록: [`docs/work-logs/2026-07-27-02-app-user-refresh-session-strategy.md`](docs/work-logs/2026-07-27-02-app-user-refresh-session-strategy.md)

## 2026-07-27 — Service-scoped Auth token provider

- 상태: Swift Package 구현·검증 완료, 운영 hosted social session과 실기기 E2E는 미구현
- 목적: 하나의 Auth 객체를 Storage·Email·Notification·Chat·Call SDK가 공유하면서 각 service audience token을 따로 요청·cache·refresh할 수 있게 한다.
- 결과: `AuthClient`를 `ServiceTokenProvider`로 확장하고 service별 session map, service-aware refresh, service별 session cache와 Keychain account suffix를 추가했다. legacy `TokenProvider` API는 `defaultService`로 동작해 기존 소비자 호환을 유지한다.
- 검증: `swift test` 15 tests 통과, `git diff --check` 통과
- 상세 기록: [`docs/work-logs/2026-07-27-01-service-scoped-auth-token-provider.md`](docs/work-logs/2026-07-27-01-service-scoped-auth-token-provider.md)

## 2026-07-25 — AuthSDK foundation cache and service expansion

- 상태: Swift Package 구현·검증 완료, 앱 E2E와 SNS 로그인은 미구현
- 목적: 모든 iOS SDK가 공통 AuthClient/token provider를 더 안정적으로 공유할 수 있도록 service audience, 환경 프리셋, session cache 경계를 보강한다.
- 결과: `AuthService.chat`·`AuthService.call`, `AuthClientConfiguration.live/local/custom`, `AuthSessionCache`, `InMemoryAuthSessionCache`, `KeychainAuthSessionCache`, cache restore/store API와 readable error surface를 추가했다.
- 검증: `swift test` 12 tests 통과
- 상세 기록: [`docs/work-logs/2026-07-25-01-auth-sdk-foundation.md`](docs/work-logs/2026-07-25-01-auth-sdk-foundation.md)

## 2026-07-24 — App-user access token refresh strategy

- 상태: Swift Package 구현·검증 완료, 운영 social/refresh session은 미구현
- 목적: AuthSDK가 단순 TokenProvider 뼈대에서 끝나지 않고 Auth Platform의 app-user token producer를 호출해 Email·Notification·Storage SDK에 줄 bearer token을 받을 수 있게 한다.
- 결과: `AuthService`와 `AppUserAccessTokenRefreshStrategy`를 추가했다. strategy는 Auth Platform internal/dev app-user token endpoint를 호출하고 project/environment/app_user/audience mismatch를 fail-closed 처리한다.
- 검증: `swift test` 6 tests 통과
- 상세 기록: [`docs/work-logs/2026-07-24-04-app-user-token-refresh-strategy.md`](docs/work-logs/2026-07-24-04-app-user-token-refresh-strategy.md)

## 2026-07-24 — AuthSDK SwiftPM release readiness

- 상태: 완료
- 목적: iOS AuthSDK를 Swift Package Manager Git URL로 붙일 수 있는 배포 준비 상태로 정리한다.
- 주요 변경 영역:
  - GitHub Actions SwiftPM CI 추가
  - README에 Git URL, branch, SemVer tag 설치 예시 추가
  - release checklist와 tag/secret 금지 기준 추가
  - HANDOFF와 상세 작업 로그 갱신
- 검증 상태: `swift package resolve`, `swift package describe`, `swift test` 4 tests, workflow YAML parse, `git diff --check` 통과
- 상세 기록: [`docs/work-logs/2026-07-24-03-auth-sdk-spm-release-readiness.md`](docs/work-logs/2026-07-24-03-auth-sdk-spm-release-readiness.md)

## 2026-07-24 — AuthSDK iOS integration guide

- 상태: 완료
- 목적: iOS 앱과 다른 SDK가 AuthSDK를 token provider로 사용하는 방식을 문서화한다.
- 주요 변경 영역:
  - README에 integration guide 링크와 미완료 경계 추가
  - `docs/guides/ios-auth-sdk-integration.md` 추가
  - HANDOFF와 상세 작업 로그 갱신
- 검증 상태: `swift test` 4 tests, 문서 파일 존재 확인, `git diff --check` 통과
- 상세 기록: [`docs/work-logs/2026-07-24-02-auth-sdk-integration-docs.md`](docs/work-logs/2026-07-24-02-auth-sdk-integration-docs.md)

## 2026-07-24 — AuthSDK token provider first slice

- 상태: 완료
- 목적: iOS AuthSDK가 다른 SDK에 주입할 수 있는 최소 `AuthClient`/`TokenProvider` 구조를 Swift Package로 부트스트랩했다.
- 주요 변경 영역:
  - Swift Package 생성
  - `AuthClient` actor와 `TokenProvider` public API 추가
  - bearer request helper와 refresh strategy 경계 추가
  - README, HANDOFF, 상세 작업 로그 생성
- 검증 상태: `swift test` 통과
- 상세 기록: [`docs/work-logs/2026-07-24-01-auth-sdk-token-provider-slice.md`](docs/work-logs/2026-07-24-01-auth-sdk-token-provider-slice.md)
