# WORKLOG

## 2026-07-24 — iOS AuthSDK 첫 패키지 골격

- 목적: Spectra Platform의 iOS SDK 순서를 Auth 우선으로 바로잡고, Notification/Storage SDK가
  주입받을 token provider 표면을 만든다.
- 결과: Swift Package, public configuration, token/session 모델, static provider, in-memory store,
  transport abstraction과 단위 테스트를 추가했다.
- 주요 변경: `Package.swift`, `Sources/SpectraAuthSDK/`, `Tests/SpectraAuthSDKTests/`,
  `README.md`, `HANDOFF.md`
- 검증: `swift test`, `git diff --check`
- 상세: [2026-07-24-01-auth-sdk-initial-slice.md](docs/work-logs/2026-07-24-01-auth-sdk-initial-slice.md)

