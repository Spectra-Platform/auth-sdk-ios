# 2026-07-24 — AuthSDK SwiftPM release readiness

## 작업 목적

`auth-sdk-ios`를 실제 앱에서 Swift Package Manager Git URL로 붙일 수 있는 배포 준비 상태로 정리한다.

## 기존 상태

- Swift Package와 public product `SpectraAuthSDK`는 이미 존재했다.
- README에는 local integration 흐름은 있었지만 Git URL 설치, SemVer tag 기준, 릴리즈 전 검증 절차와 CI 기준이 부족했다.
- GitHub Actions workflow는 없었다.

## 적용 내용

- `.github/workflows/ci.yml`을 추가해 push, pull request, `v*` tag에서 SwiftPM 검증을 실행하도록 했다.
- README에 Git URL 설치 예시, branch 사용 예시, SemVer tag 사용 예시와 product dependency 이름을 추가했다.
- `docs/guides/release-checklist.md`를 추가해 배포 단위, 버전 정책, tag 절차, secret 금지 기준과 릴리즈 전 검증을 정리했다.
- `HANDOFF.md`와 `WORKLOG.md`에 SwiftPM 배포 경계와 현재 미완료 항목을 반영했다.

## 주요 변경 파일

- `.github/workflows/ci.yml`
- `README.md`
- `docs/guides/release-checklist.md`
- `HANDOFF.md`
- `WORKLOG.md`
- `docs/work-logs/2026-07-24-03-auth-sdk-spm-release-readiness.md`

## 검증

- `swift package resolve`
- `swift package describe`
- `swift test`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml")'`
- `git diff --check`

## 남은 작업

- 최초 공개 버전 번호를 확정한 뒤 `v0.1.0` 같은 SemVer tag를 생성한다.
- Apple/Google native sign-in, Auth social exchange, Keychain refresh session, rotation/revocation은 Auth Platform producer API 구현 후 별도 작업으로 연결한다.

## 커밋 기록

- 이번 작업 커밋에서 기록한다.
