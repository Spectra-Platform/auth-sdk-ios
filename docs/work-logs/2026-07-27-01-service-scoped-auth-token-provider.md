# 2026-07-27 — Service-scoped Auth token provider

## 작업 목적과 이해한 내용

하나의 iOS `AuthClient`를 StorageSDK, Email/NotificationSDK, ChatSDK, CallSDK가 함께 사용하되 각 SDK가 자기 service audience에 맞는 app-user access token을 요청할 수 있게 한다.

기존 `TokenProvider` 소비자는 깨지지 않아야 하며, 신규 SDK는 `ServiceTokenProvider`를 통해 service를 명시한다.

## 문제 진단 또는 기존 동작

- `AuthClient`는 단일 session만 보관했다.
- `AppUserAccessTokenRefreshStrategy`는 생성 시 고정한 service 하나만 refresh할 수 있었다.
- 여러 SDK가 같은 Auth 객체를 공유하면 storage token cache가 notification/chat/call 요청에 섞일 수 있는 경계가 있었다.
- 기존 테스트의 refresh fixture는 fixed clock과 60초 leeway 기준에서 만료 token으로 판정될 수 있었다.

## 적용한 내용과 주요 변경 파일

- `Sources/SpectraAuthSDK/TokenProvider.swift`
  - `ServiceTokenProvider` protocol과 service별 authorization helper를 추가했다.
  - `AccessToken`에 audience/service validation helper를 추가했다.
- `Sources/SpectraAuthSDK/AuthClient.swift`
  - `AuthClient`를 service별 session map 기반으로 변경했다.
  - legacy `getAccessToken(forceRefresh:)`는 `defaultService`로 동작하게 유지했다.
  - `getAccessToken(for:)`, `refresh(for:)`, service별 cache restore/clear 경계를 추가했다.
- `Sources/SpectraAuthSDK/AuthTokenRefreshStrategy.swift`
  - `ServiceScopedAuthTokenRefreshStrategy`, `ServiceAwareAuthTokenRefreshStrategy`를 추가했다.
- `Sources/SpectraAuthSDK/AppUserAccessTokenRefreshStrategy.swift`
  - service-aware refresh 요청을 지원해 요청 service별 token을 발급받게 했다.
- `Sources/SpectraAuthSDK/AuthSessionCache.swift`, `KeychainAuthSessionCache.swift`
  - service별 session cache를 추가했다.
  - Keychain은 account suffix `#<service>`로 service session을 분리한다.
- `Tests/SpectraAuthSDKTests/AuthClientTests.swift`
  - service별 cache, service별 force refresh, audience mismatch 차단 회귀 테스트를 추가했다.

## 실행한 검증과 결과

- `swift test` — 15 tests 통과
- `git diff --check` — 통과

## 남은 작업, 미검증 항목 또는 주의사항

- Apple/Google native sign-in entrypoint와 Auth social exchange API는 아직 미구현이다.
- 운영용 app-user refresh session, refresh token rotation, reuse detection, logout revocation은 아직 미구현이다.
- JWKS/signing key 또는 introspection 최종 정책은 아직 미확정이다.
- 실제 Spectra iOS 앱 실기기 E2E는 이번 범위에서 수행하지 않았다.

## 커밋 기록

- 이번 구현 커밋에 포함한다.
