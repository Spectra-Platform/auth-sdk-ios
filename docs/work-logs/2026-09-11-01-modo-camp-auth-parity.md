# 2026-09-11 — Modo Camp Auth parity draft

## 작업 목적과 이해한 내용

Modo Camp iOS SwiftUI 앱이 React 웹의 `@spectra-platform/auth-sdk@0.1.11`과
같은 의미의 Auth SDK를 사용할 수 있도록 Swift public API 목표와 callback
경계를 문서화했다.

## 문제 진단 또는 기존 동작

기존 `auth-sdk-ios`는 token provider, service token provider, Keychain session
cache와 public dev/mock session strategy를 갖고 있지만, Google/Apple hosted
login, ASWebAuthenticationSession callback, `preflightSignIn(provider, options)`
같은 production login surface는 아직 구현되지 않았다.

## 적용한 내용과 주요 변경 파일

- `docs/guides/modo-camp-ios-auth-parity.md`
  - Modo Camp production 설정, Swift Auth API 초안, callback/deep link 가이드,
    backend bootstrap token 경계, redaction 규칙, JS parity checklist를 추가했다.
- `README.md`, `HANDOFF.md`, `WORKLOG.md`
  - Modo Camp parity guide와 현재 미구현 경계를 연결했다.

## 실행한 검증과 결과

- 문서 변경만 수행했다. Swift code와 Package manifest는 변경하지 않았다.
- `git diff --check`로 whitespace 검증이 필요하다.

## 남은 작업, 미검증 항목 또는 주의사항

- Google/Apple social exchange producer 계약과 ASWebAuthenticationSession
  callback 구현은 후속 코드 slice에서 처리한다.
- 실제 Modo Camp bundle ID, callback URL scheme, Universal Link domain 등록은
  앱/Console 설정과 함께 검증해야 한다.
- Auth access token은 Modo backend bootstrap용이며, Storage/Chat/Notification
  service token을 bootstrap에 사용하면 안 된다.
