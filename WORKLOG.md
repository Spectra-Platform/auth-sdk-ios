# WORKLOG

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
