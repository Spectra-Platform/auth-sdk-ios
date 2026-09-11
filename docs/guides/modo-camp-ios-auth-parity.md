# Modo Camp iOS Auth SDK parity draft

Last checked: 2026-09-11

This guide fixes the Swift Auth SDK target for Modo Camp iOS. It is based on
the local `@spectra-platform/auth-sdk@0.1.11` source and the current
`auth-sdk-ios` implementation. It is a contract draft, not proof that the
Apple/Google production login flow is already implemented on iOS.

## Current state

- Existing SwiftPM package: `SpectraAuthSDK`
- Current iOS package implements configuration, token provider, service token
  provider, refresh strategies, Keychain session cache and dev/mock public
  app-user session support.
- Current iOS package does not yet implement Google/Apple native sign-in,
  ASWebAuthenticationSession hosted login, Universal Link callback exchange or
  `preflightSignIn(provider, options)` as an app-facing login API.
- JS parity source: `@spectra-platform/auth-sdk@0.1.11`

## Recommended package structure

Keep the existing separate SwiftPM package:

```swift
.package(
    url: "https://github.com/Spectra-Platform/auth-sdk-ios.git",
    .upToNextMinor(from: "0.1.0")
)
```

Do not create a new mono-package for this slice. Auth, Storage, Chat and
Notification already exist as separate packages and can evolve independently.
A future `SpectraCoreSDK` may compose shared configuration, diagnostics and
transport after the four packages expose JS-parity APIs.

## Modo Camp production configuration

```swift
let auth = SpectraAuthClient(
    configuration: .live(
        baseURL: URL(string: "https://auth.spectra.kr")!,
        projectId: "13d7ce4b-dd2a-4267-b15f-bbdb80b853da",
        publicClientId: "app_sOULkwyuWH_UeH2Cy7Dj0CKb",
        redirectURI: URL(string: "modocamp://spectra-auth/callback")!
    ),
    sessionStore: KeychainAuthSessionCache(
        account: "13d7ce4b-dd2a-4267-b15f-bbdb80b853da:auth"
    )
)
```

For local or staging QA, use `.custom(...)` with `environment: .test` and a
local Auth base URL. Do not put provider secrets, project API tokens, Apple
private keys, Google client secrets or raw authorization codes in the app
bundle or diagnostics.

## Swift public API target

```swift
public enum SpectraAuthProvider: String, Sendable {
    case google
    case apple
}

public enum SpectraAuthSignInPrompt: String, Sendable {
    case selectAccount = "select_account"
}

public struct SpectraAuthSignInOptions: Sendable {
    public var redirectURI: URL?
    public var prompt: SpectraAuthSignInPrompt?
    public var timeout: Duration?
    public var prefersEphemeralWebBrowserSession: Bool
}

public struct SpectraGetAccessTokenOptions: Sendable {
    public var forceRefresh: Bool
    public var service: AuthService?
}

public actor SpectraAuthClient: ServiceTokenProvider {
    public var currentSession: AuthSession? { get async }
    public func getSession() async -> AuthSession?

    public func preflightSignIn(
        _ provider: SpectraAuthProvider,
        options: SpectraAuthSignInOptions
    ) throws

    public func signInWithGoogle(
        options: SpectraAuthSignInOptions
    ) async throws -> AuthSession

    public func signInWithApple(
        options: SpectraAuthSignInOptions
    ) async throws -> AuthSession

    public func signIn(
        _ provider: SpectraAuthProvider,
        options: SpectraAuthSignInOptions
    ) async throws -> AuthSession

    public func handleCallback(url: URL) async throws -> Bool
    public func getAccessToken(
        _ options: SpectraGetAccessTokenOptions
    ) async throws -> AccessToken
    public func refresh() async throws -> AuthSession
    public func logout(
        endBrowserSession: Bool,
        postLogoutRedirectURI: URL?
    ) async throws
}
```

The default `getAccessToken()` must return the Auth session access token. Modo
Camp backend bootstrap should call `POST /v1/me/bootstrap` with this token as
`Authorization: Bearer`. Storage, Chat and Notification service tokens are
requested only by their SDKs and must not be used for backend bootstrap.

## Callback and deep link guide

Custom scheme setup:

1. Register a scheme such as `modocamp` in `CFBundleURLTypes`.
2. Register `modocamp://spectra-auth/callback` in the Spectra Auth app client.
3. In SwiftUI, forward `.onOpenURL` to `auth.handleCallback(url:)`.

Universal Link setup:

1. Add the app domain to Associated Domains, for example
   `applinks:app.modocamp.example`.
2. Register the HTTPS callback path with the Spectra Auth app client.
3. Route the Universal Link to `auth.handleCallback(url:)`.

The SDK implementation should use `ASWebAuthenticationSession` for hosted
login unless the app explicitly uses Universal Link-only routing. The SDK must
validate state and callback URI before exchanging the authorization code.

## Diagnostics and errors

Expose only safe fields:

- `code`
- `status`
- `requestId`
- `message`
- `retryAfterSeconds` when present

Never log access tokens, refresh tokens, ID tokens, authorization codes, raw
provider payloads or email addresses. User summary fields may be exposed to app
code, but diagnostics should redact email-like values.

## JS to Swift parity checklist

| JS 0.1.11 | Swift target | Current iOS state |
| --- | --- | --- |
| `preflightSignIn(options)` | `preflightSignIn(provider, options)` | Missing app-facing API |
| `signInWithGoogle(options)` | `signInWithGoogle(options:)` | Missing production login |
| `signInWithApple(options)` | `signInWithApple(options:)` | Missing production login |
| `getSession()` | `getSession()` / `currentSession` | Partial session state exists |
| `getAccessToken()` | `getAccessToken()` | Implemented as token provider |
| `getAccessToken({ service })` | `getAccessToken(service:)` | Implemented low-level service provider |
| `refresh()` | `refresh()` | Implemented for current strategies |
| `logout({ endBrowserSession })` | `logout(endBrowserSession:postLogoutRedirectURI:)` | Logout exists; hosted browser end-session target missing |
| localStorage session store | Keychain session store | Implemented |
| popup callback relay | ASWebAuthenticationSession/deep link callback | Missing |
