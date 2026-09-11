# 2026-09-11 — Modo Camp production hosted login slice

## 작업 목적과 이해한 내용

Modo Camp iOS SwiftUI 앱에서 JS `@spectra-platform/auth-sdk@0.1.11`과 같은 의미로 사용할 수 있는
`SpectraAuthSDK` hosted login slice를 구현한다. 기본 Auth access token은 Modo backend bootstrap bearer proof이며,
Storage/Chat/Notification service token은 각 SDK 내부 요청용으로만 사용한다.

## 문제 진단 또는 기존 동작

- 기존 iOS SDK는 `AuthClient`, service token provider, Keychain session cache, public `dev_mock` session 전략을 제공했다.
- Google/Apple hosted login, PKCE/state/nonce challenge, authorization code exchange, app-facing
  `preflightSignIn`/`signInWithGoogle`/`signInWithApple`, Auth session refresh/logout endpoint는 구현되어 있지 않았다.
- 기존 `TokenProvider.refresh() -> AccessToken` public API가 있어 JS parity의 full-session `refresh()`와 이름이 충돌했다.

## 적용한 내용과 주요 변경 파일

- `Package.swift`
  - iOS minimum을 17, macOS minimum을 14로 올렸다.
- `Sources/SpectraAuthSDK/HostedAuthSessionStrategy.swift`
  - `SpectraAuthClient` alias, `SpectraAuthProvider`, `SpectraAuthSignInOptions`, `SpectraGetAccessTokenOptions`,
    `HostedAuthSessionStrategy`, `SpectraWebAuthenticationSessionProvider`, `ASWebAuthenticationSessionProvider`를 추가했다.
  - `/platform/v1/auth/social/challenges`, `/platform/v1/auth/social/exchanges`,
    `/platform/v1/auth/sessions/refresh`, `DELETE /platform/v1/auth/sessions/current`,
    `/platform/v1/auth/sessions/current/access-tokens` 호출을 구현했다.
  - PKCE S256, state/nonce, Keycloak provider alias, callback redirect/state 검증, timeout/cancellation 경계를 추가했다.
- `Sources/SpectraAuthSDK/AuthClient.swift`
  - `currentSession`, `getSession`, `refreshSession`, `logout(endBrowserSession:postLogoutRedirectURI:)`,
    `preflightSignIn`, `signInWithGoogle`, `signInWithApple`, `signIn`, `handleCallback(url:)` 연결을 추가했다.
  - 기존 `TokenProvider.refresh() -> AccessToken`은 호환성을 위해 유지하고 full Auth session refresh는
    `refreshSession()`으로 제공한다.
- `Sources/SpectraAuthSDK/AuthClientConfiguration.swift`
  - `AuthService.auth`를 추가해 Auth session token과 service token의 의미를 분리했다.
- `Sources/SpectraAuthSDK/AuthError.swift`
  - JS SDK와 같은 방향의 safe public error fields인 `code`, `status`, `requestId`, `message`,
    `retryAfterSeconds`를 추가했다.
- `Sources/SpectraAuthSDK/AuthSession.swift`
  - hosted Auth session 응답의 `isNewAppUser`, safe OIDC `idToken`, user summary를 담을 수 있게 확장했다.
- `Tests/SpectraAuthSDKTests/AuthClientTests.swift`
  - hosted Google sign-in challenge/authorization/exchange/cache, service token 경계, refresh/logout endpoint,
    callback mismatch 테스트를 추가했다.
- `README.md`, `HANDOFF.md`, `docs/guides/modo-camp-ios-auth-parity.md`,
  `docs/guides/ios-auth-sdk-integration.md`, `WORKLOG.md`
  - 구현 상태, 사용 예제, 남은 검증 범위를 갱신했다.

## 실행한 검증과 결과

- `swift test`: 22 tests 통과
- `git diff --check`: 통과

## 남은 작업, 미검증 항목 또는 주의사항

- 실제 Modo Camp iOS 앱, iOS 시뮬레이터, 실기기에서 Google/Apple hosted login 왕복은 아직 검증하지 않았다.
- Universal Link-only helper와 callback URL 생성 public helper는 확장 포인트로 남아 있다.
- ASWebAuthenticationSession presentation context가 필요한 앱은 `ASWebAuthenticationSessionProvider`에 앱의
  `ASWebAuthenticationPresentationContextProviding` 구현을 주입한다.
- access token, refresh token, authorization code, provider credential, 이메일 원문은 로그와 진단 출력에 남기지 않는다.
