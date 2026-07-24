# 2026-07-24 — AuthSDK iOS initial slice

## 작업 목적

Spectra Platform SDK 개발 순서를 Auth 우선으로 정리한다. iOS 앱이 Project API token이나 provider
secret을 직접 들고 있지 않게 하고, NotificationSDK와 StorageSDK가 AuthSDK의 app-user access token
provider를 받아 사용하는 구조의 첫 발판을 만든다.

## 문제 진단

- `auth-sdk-ios` 저장소는 생성돼 있었지만 아직 Swift Package 코드가 없었다.
- `notification-sdk-ios`는 자체 `SpectraAccessTokenProviding` 프로토콜을 이미 갖고 있어 downstream
  SDK가 token provider를 받는 방향은 맞다.
- `auth-platform`의 공개 hosted login/social exchange/refresh session 계약은 아직 미완료다. 따라서
  SDK에서 실제 로그인 네트워크 메서드를 확정 구현하면 계약보다 앞서가게 된다.

## 적용 내용

- Swift Package `SpectraAuthSDK`를 추가했다.
- public configuration과 environment model을 추가했다.
- `SpectraAccessTokenProviding`과 `SpectraAuthClient`를 추가해 AuthSDK 자체가 token provider가 되게 했다.
- local package 연동과 테스트를 위한 `StaticSpectraAccessTokenProvider`를 추가했다.
- Keychain 구현 전 단계로 `SpectraAuthSessionStoring`과 `InMemorySpectraAuthSessionStore`를 추가했다.
- future endpoint 연결을 위한 `SpectraAuthTransport`와 `URLSessionSpectraAuthTransport`를 추가했다.
- README/HANDOFF/WORKLOG를 추가해 현재 경계와 후속 작업을 명시했다.

## 검증

- `swift test`
- `git diff --check`

## 남은 작업

- hosted login / social provider exchange 공개 계약 확정
- Keychain session store 구현
- AuthSDK access token refresh와 logout revocation 구현
- NotificationSDK가 AuthSDK provider를 직접 소비하도록 의존성 정리
- Spectra iOS 앱에 local package로 연결해 실제 빌드 검증

## 커밋 기록

- 이번 작업 커밋은 최종 커밋 후 `WORKLOG.md` 인덱스와 함께 추적한다.

