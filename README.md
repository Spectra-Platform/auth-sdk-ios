# Spectra Auth SDK for iOS

Local Swift Package for Spectra Platform Auth integration.

Implemented first slice:

- `SpectraAuthClient` as an app-side token provider surface
- `SpectraAuthConfiguration` with public project/client configuration only
- `SpectraAccessTokenProviding` protocol compatible with downstream SDK token injection
- `StaticSpectraAccessTokenProvider` and `InMemorySpectraAuthSessionStore` for local tests
- HTTP transport abstraction for future hosted login / social exchange endpoints

Current boundary:

- Do not put Project API tokens, provider secrets, Apple `.p8`, Google client secrets, or server-only credentials in an iOS app bundle.
- Public hosted login, social provider exchange, refresh token rotation, Keychain persistence, and JWKS/session revocation are not implemented yet.
- This package is intentionally usable as a local Swift Package before package registry publishing.

Minimal local usage:

```swift
import SpectraAuthSDK

let auth = SpectraAuthClient(
    configuration: SpectraAuthConfiguration(
        baseURL: URL(string: "https://auth.spectra.kr")!,
        projectId: "project-id",
        publicClientId: "app_public_client",
        environment: .test
    ),
    tokenProvider: StaticSpectraAccessTokenProvider(token: "development-access-token")
)

let token = try await auth.accessToken()
```

