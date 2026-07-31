# 2026-07-25 — AuthSDK foundation cache and service expansion

## 작업 목적과 이해한 내용

- iOS SDK 구현 순서의 첫 단계로 AuthSDK를 모든 SDK가 공유할 수 있는 token provider foundation으로 보강한다.
- 이번 범위는 `auth-sdk-ios` 내부 구현과 단위 검증이며 Spectra iOS 앱, 다른 SDK, SNS 로그인 구현은 포함하지 않는다.

## 문제 진단 또는 기존 동작

- `AuthService`는 `storage`, `email`, `notification`만 지원해 ChatSDK/CallSDK audience 요청을 표현할 수 없었다.
- `AuthClientConfiguration`은 매번 `baseURL`, `projectId`, `publicClientId`, `environment`를 직접 구성해야 했다.
- session은 actor 내부 memory 또는 `initialSession`에만 존재했고, 앱 재실행 후 복구할 수 있는 cache boundary가 없었다.
- configuration/cache 실패를 앱에서 설명하기 쉬운 오류로 구분하는 surface가 부족했다.

## 적용한 내용과 주요 변경 파일

- `Sources/SpectraAuthSDK/AuthClientConfiguration.swift`
  - `AuthService.chat`, `AuthService.call` 추가
  - `live`, `local`, `custom` configuration factory와 `validated()` 추가
- `Sources/SpectraAuthSDK/AuthSessionCache.swift`
  - `AuthSessionCache` protocol과 `InMemoryAuthSessionCache` 추가
- `Sources/SpectraAuthSDK/KeychainAuthSessionCache.swift`
  - iOS/macOS Security framework 기반 Keychain session cache surface 추가
- `Sources/SpectraAuthSDK/AuthClient.swift`
  - optional session cache 주입
  - refresh 성공 시 cache 저장
  - `restoringCachedSession(...)`, `restoreSessionFromCache()`, `clearSessionCache()` 추가
  - 기존 `initialSession`과 `TokenProvider` surface 유지
- `Sources/SpectraAuthSDK/AuthError.swift`
  - readable configuration/cache error와 `LocalizedError` 설명 추가
- `Sources/SpectraAuthSDK/AuthSession.swift`, `Sources/SpectraAuthSDK/TokenProvider.swift`
  - cache 저장을 위해 `AuthSession`, `AppUser`, `AccessToken`을 `Codable`로 확장
- `Tests/SpectraAuthSDKTests/AuthClientTests.swift`
  - service expansion, configuration preset/validation, cache restore/store 테스트 추가
- `README.md`
  - 새 configuration/cache 사용 예시와 미완료 경계 갱신

## 실행한 검증과 결과

- `swift test`
  - 결과: 12 tests 통과

## 남은 작업, 미검증 항목 또는 주의사항

- Spectra iOS 앱 SPM integration과 실제 앱 E2E는 후속 단계에서 수행한다.
- 후속 iOS 앱/시뮬레이터 검증은 Google 로그인 세션 대신 사용자가 지정한 테스트유저 1/테스트유저 2와 초기화 기능을 사용한다.
- SNS 로그인, hosted social exchange, refresh token rotation/reuse detection/logout revocation은 후속 AuthSDK/API 단계로 남긴다.
- Keychain cache는 Security framework surface와 단위 compile까지 검증했으며, 실제 앱 Keychain entitlement/access group 조합은 앱 integration 단계에서 확인한다.

## 커밋 기록

- 예정: `feat: expand auth sdk foundation`
