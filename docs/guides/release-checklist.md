# AuthSDK iOS Release Checklist

이 문서는 `auth-sdk-ios`를 Swift Package Manager로 배포할 때 확인할 기준이다. 현재 배포 방식은 Git URL 기반 SwiftPM package이며, 앱 쪽에서는 branch 또는 SemVer tag로 의존성을 고정한다.

## 배포 단위

- Repository: `https://github.com/Spectra-Platform/auth-sdk-ios.git`
- Swift package name: `spectra-auth-sdk-ios`
- Library product: `SpectraAuthSDK`
- Minimum platform: iOS 15, macOS 12
- Swift tools version: 5.9

## 앱에서 추가하는 방법

개발 중 branch 의존성:

```swift
.package(
    url: "https://github.com/Spectra-Platform/auth-sdk-ios.git",
    branch: "main"
)
```

릴리즈 후 권장 의존성:

```swift
.package(
    url: "https://github.com/Spectra-Platform/auth-sdk-ios.git",
    .upToNextMinor(from: "0.1.0")
)
```

product:

```swift
.product(name: "SpectraAuthSDK", package: "auth-sdk-ios")
```

## 버전 정책

- tag는 `vMAJOR.MINOR.PATCH` 형식을 사용한다. 예: `v0.1.0`
- `0.x` 구간에서는 public API 변경이 잦을 수 있으므로 앱은 `.upToNextMinor` 또는 exact version을 우선 사용한다.
- public type, initializer, protocol requirement 변경은 `CHANGELOG.md` 또는 release note에 적는다.
- secret, sample token, 운영 endpoint credential은 tag에 포함하지 않는다.

## 릴리즈 전 로컬 검증

```bash
swift package resolve
swift package describe
swift test
git diff --check
```

CI도 같은 범위를 검증한다.

## tag 생성 절차

버전 번호가 확정된 뒤에만 tag를 만든다.

```bash
git status --short
git tag -a v0.1.0 -m "AuthSDK iOS 0.1.0"
git push origin v0.1.0
```

## 릴리즈 전 확인 항목

- README의 설치 URL과 product 이름이 실제 `Package.swift`와 일치한다.
- `Package.swift`에 local path dependency가 없다.
- `.build`, `.swiftpm`, DerivedData, Xcode user state가 commit에 포함되지 않는다.
- 앱 bundle에 넣으면 안 되는 secret이 문서 예제나 테스트 fixture에 포함되지 않는다.
- `AuthClientConfiguration`에는 공개 가능한 값만 유지한다.
- StorageSDK·NotificationSDK는 `AuthClient` concrete type이 아니라 token provider protocol 경계로 연동한다.

## 현재 배포 경계

이 체크리스트는 SwiftPM package 배포 가능 상태를 다룬다. 아직 다음 항목은 구현 완료가 아니다.

- Apple/Google native sign-in entrypoint
- Auth Platform social exchange API
- Keychain refresh session 저장
- refresh token rotation/reuse detection/logout revocation
- 실제 Spectra iOS 앱의 운영 E2E
