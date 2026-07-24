# iOS AuthSDK token provider first slice

## 작업 목적과 이해한 내용

iOS AuthSDK의 첫 구현 slice로, StorageSDK·NotificationSDK 같은 다른 SDK가 Project API token이나 provider secret을 직접 받지 않고 AuthSDK의 token provider에서 app-user bearer token을 얻도록 하는 최소 구조를 만든다.

이번 범위는 public API를 크게 고정하지 않고 다음 경계만 구현한다.

- Auth client configuration과 base URL
- `TokenProvider` async interface
- bearer request attachment helper
- token cache/expiry와 refresh를 나중에 붙일 수 있는 경계
- Swift Package 단위 테스트

## 문제 진단 또는 기존 동작

`auth-sdk-ios`는 Git만 초기화된 빈 저장소였고, `README.md`, `HANDOFF.md`, `WORKLOG.md`, Swift Package 파일이 없었다.

Auth Platform의 현재 구현은 Console account/session과 Project API token 중심이며, app-user social login, access/refresh session, JWKS 또는 app-user introspection producer는 아직 구현되지 않았다. 따라서 SDK는 실제 로그인·refresh HTTP를 구현하지 않고 provider 경계와 in-memory session/cache 동작까지만 제공해야 한다.

## 적용한 내용과 주요 변경 파일

- `Package.swift`
  - Swift 5.9 Package `SpectraAuthSDK` 생성
  - iOS 15, macOS 12 최소 platform 지정
- `Sources/SpectraAuthSDK/AuthClient.swift`
  - `AuthClient` actor 추가
  - 만료되지 않은 access token cache 반환
  - 만료 또는 강제 refresh 시 `AuthTokenRefreshStrategy` 호출
  - 기본 refresh는 서버 구현 전까지 `AuthError.refreshUnavailable`로 fail-closed
- `Sources/SpectraAuthSDK/TokenProvider.swift`
  - `TokenProvider` protocol 추가
  - `authorizationHeader`와 `authorizedRequest` helper 추가
  - `AccessToken`의 expiry, scope, audience 모델 추가
- `Sources/SpectraAuthSDK/AuthClientConfiguration.swift`
  - `baseURL`, `projectId`, `publicClientId`, `environment`, `redirectURI` configuration 추가
- `Sources/SpectraAuthSDK/AuthSession.swift`
  - 현재 user와 access token session 모델 추가
- `README.md`, `HANDOFF.md`, `WORKLOG.md`
  - 모바일 secret 금지, SDK 주입 방식, 구현/미구현 경계 기록

## 실행한 검증과 결과

- `swift test` — 통과
- `git diff --check` — 통과

## 남은 작업, 미검증 항목 또는 주의사항

- 실제 소셜 로그인, Apple/Google provider 연동은 제외했다.
- Keychain 영구 저장과 refresh token rotation/reuse detection은 제외했다.
- Auth Platform Identity Plane의 app-user session producer와 계약이 아직 planned 상태라 실제 서버 E2E는 수행하지 않았다.
- 실제 iOS 앱, simulator, 실기기 검증은 수행하지 않았다.
- 앱 bundle에는 Project API token, provider client secret, Apple private key, Console session cookie를 넣으면 안 된다.

## 커밋 기록

- `a6cfaab feat: bootstrap ios auth token provider` — Swift Package 부트스트랩, `AuthClient`/`TokenProvider` public surface, bearer helper, refresh 경계, unit test와 연속성 문서
