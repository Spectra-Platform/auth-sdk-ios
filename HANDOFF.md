# HANDOFF

## 목적과 소유 범위

`auth-sdk-ios`는 iOS 앱이 Spectra Platform Auth를 사용할 때 가져가는 공개 클라이언트 SDK다.
앱 번들에는 공개 가능한 Project/App Client 설정만 넣고, 서버 전용 Project API token이나 provider
secret은 포함하지 않는다.

## 확정된 결정

- iOS SDK는 Android/JavaScript보다 먼저 기준 SDK로 만든다.
- SDK 설정에는 `baseURL`, `projectId`, `publicClientId`, `environment`처럼 공개 가능한 값만 둔다.
- downstream SDK(Notification/Storage)는 AuthSDK가 제공하는 app-user access token provider에서 token을
  받아 사용한다.
- 이번 첫 slice는 실제 hosted login이나 refresh session을 구현하지 않고, token provider surface와
  local test용 static/in-memory provider를 먼저 제공한다.
- Project API token은 Console/server-side workload용이며 iOS 앱에 직접 넣지 않는다.

## 현재 구현 경계

- `SpectraAuthClient`는 `SpectraAccessTokenProviding`을 구현한다.
- `StaticSpectraAccessTokenProvider`는 로컬 패키지 연동과 테스트를 위한 임시 provider다.
- `InMemorySpectraAuthSessionStore`는 Keychain persistence 이전 단계의 테스트 저장소다.
- HTTP transport abstraction은 준비됐지만 공개 login/exchange endpoint 계약이 아직 확정되지 않아
  실제 네트워크 로그인 메서드는 제공하지 않는다.

## 함께 확인할 저장소

- `Spectra-Platform/auth-platform`: 공개 Auth API, app-user token/session 계약
- `Spectra-Platform/notification-sdk-ios`: Auth token provider를 소비할 iOS Push SDK
- `Spectra-Platform/storage-sdk-ios`: Auth token provider를 소비할 iOS Storage SDK 예정
- `spectra-ios`: 실제 앱에 local package로 연결해 검증할 대상

## 남은 작업

- hosted login / social provider exchange 공개 계약 확정
- access/refresh token 모델과 rotation·reuse detection·logout revocation 공개화
- Keychain 기반 session store 구현
- NotificationSDK/StorageSDK가 AuthSDK provider를 직접 받도록 의존성 정리
- 실제 Spectra 앱 local package 연동과 실기기 E2E

마지막 코드 대조: 2026-07-24

