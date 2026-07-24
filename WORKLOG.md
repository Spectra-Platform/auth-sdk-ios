# WORKLOG

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
