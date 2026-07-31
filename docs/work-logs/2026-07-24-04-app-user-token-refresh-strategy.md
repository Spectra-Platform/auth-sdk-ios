# App-user access token refresh strategy

## 목적

AuthSDK가 `TokenProvider` protocol과 in-memory cache만 제공하던 상태에서 한 단계 더 나아가,
Auth Platform의 app-user token producer를 호출해 Email·Notification·Storage SDK에 넘길 bearer
token을 받을 수 있게 한다.

## 기존 동작

- `AuthClient`는 만료된 token에서 `AuthTokenRefreshStrategy`를 호출할 수 있었지만 기본 strategy는
  `refreshUnavailable`로 닫혀 있었다.
- 실제 Auth Platform HTTP endpoint를 호출하는 SDK surface가 없었다.
- service/audience는 sample fixture 수준에서 Storage 중심으로만 나타났다.

## 적용 내용

- `AuthService` enum을 추가해 token마다 `storage`, `email`, `notification` 중 하나의 service를
  요청할 수 있게 했다.
- `AppUserAccessTokenRefreshStrategy`를 추가했다.
  - `POST /internal/dev/v1/app-user-access-tokens` 호출
  - `project_id`, `public_client_id`, `environment`, `service`, `app_user_id`, optional `ttl_seconds`
    body 생성
  - optional additional headers 지원
  - response의 project/environment/app_user/audience mismatch를 `invalidTokenResponse`로 fail-closed
- `AuthError.tokenRefreshFailed(statusCode:)`와 `invalidConfiguration`을 추가했다.
- unit test로 email service token request body, header, response decoding, mismatched audience failure를
  고정했다.

## 검증

- `swift test` 통과
  - 6 tests

## 남은 작업

- 현재 strategy는 local/dev bridge용이다. 운영 앱 bundle에는 internal key를 넣으면 안 된다.
- Apple/Google native sign-in, hosted/social exchange, Keychain refresh session, rotation/revocation은
  Auth Platform producer API 구현 후 별도 작업으로 연결한다.

## 커밋 기록

- 이번 작업 완료 후 별도 커밋에 기록한다.
