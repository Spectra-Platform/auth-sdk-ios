# 2026-07-24 — AuthSDK iOS integration guide

## 작업 목적

`auth-sdk-ios`의 첫 token provider slice를 iOS 앱과 다른 SDK가 어떻게 사용해야 하는지 문서화한다.

## 기존 상태

- README에는 기본 `AuthClient` 생성 예제가 있었다.
- local package integration, public config와 secret 경계, NotificationSDK adapter 예제는 별도 문서로 정리되어 있지 않았다.

## 적용 내용

- `README.md`
  - integration guide 링크 추가
  - 현재 미완료 경계 추가
- `HANDOFF.md`
  - iOS integration guide 위치 기록
- `WORKLOG.md`
  - 이번 문서 작업 인덱스 추가
- `docs/guides/ios-auth-sdk-integration.md`
  - local Swift Package 연결 방법
  - public config와 금지 secret 구분
  - `AuthClient`, `getAccessToken`, `authorizedRequest`, `logout` 예제
  - NotificationSDK adapter 예제
  - 미완료 social login/refresh-session 경계 정리

## 검증

- `swift test` 4 tests 통과.
- 문서 파일 존재 확인 통과.
- `git diff --check` 통과.

## 남은 작업

- 실제 social login API producer 구현 후 guide 갱신
- Keychain refresh session 구현 후 persistence guide 추가
- Spectra iOS local package integration 후 실제 app 코드 기준 예제 보정

## 커밋 기록

- `docs: add auth sdk integration guide`
