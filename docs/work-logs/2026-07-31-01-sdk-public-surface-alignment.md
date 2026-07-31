# SDK public surface alignment

## 작업 목적과 이해한 내용

AuthSDK는 다른 개별 SDK가 공통 session과 token provider를 공유할 수 있게 해야 하지만, 앱 개발자가 처음 보는
public 예시가 service audience, 내부 token exchange, server-side 용어 중심이면 안 된다. 또한 Core SDK를 먼저
강제하지 않고 Auth/Notification/Storage/Chat/Call 개별 SDK를 먼저 안정화한 뒤, future Core SDK가 그 SDK들을
조합하는 방향을 문서에 고정해야 한다.

## 문제 진단 또는 기존 동작

- README가 `service audience token`을 개별 SDK 사용의 주요 설명으로 노출했다.
- HANDOFF에는 Core SDK보다 개별 SDK를 먼저 만든다는 현재 제품 방향이 명시되어 있지 않았다.
- 코드 public API에는 `ServiceTokenProvider`, `AuthService`, token audience가 이미 존재한다. 이를 즉시 제거하면
  기존 SDK 간 token provider 경계를 깨뜨릴 수 있으므로 이번 작업은 app-facing 문서와 handoff 정리에 집중했다.

## 적용한 내용과 주요 변경 파일

- `README.md`
  - 개별 SDK 우선 제작 후 future Core SDK가 조합한다는 방향을 추가했다.
  - `ServiceTokenProvider`를 앱 화면 코드가 직접 다루는 개념이 아니라 개별 SDK 패키지 내부의 low-level 기능 token 경계로 설명했다.
- `HANDOFF.md`
  - Core SDK를 Auth SDK보다 먼저 만들지 않는다는 결정을 추가했다.
  - app-facing 문서와 예시는 service audience나 내부 token exchange보다 로그인과 개별 SDK 사용 흐름을 먼저 보여주도록 기록했다.
  - future Core SDK/convenience 경계를 남은 작업에 추가했다.
- `WORKLOG.md`
  - 이번 문서 보정과 검증 기준을 기록했다.

## 실행한 검증과 결과

- `swift test`
  - 통과: 18 tests, 0 failures
- `git diff --check`
  - 통과

## 남은 작업, 미검증 항목 또는 주의사항

- `ServiceTokenProvider`/`AuthService` public API 자체는 compatibility 때문에 유지했다.
- Apple/Google real sign-in entrypoint와 Hosted Login/social exchange SDK API는 아직 구현하지 않았다.
- Core SDK는 이번 작업에서 생성하지 않았고, 개별 SDK public API가 안정된 뒤 조합 계층으로 설계해야 한다.
