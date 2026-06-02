# Contributing to Nautilarr

Thanks for your interest! Nautilarr is an original, clean-room project. A few
ground rules keep it that way and keep the codebase maintainable.

## Originality

- Integrate against services' **public, documented REST APIs** only.
- Do **not** copy code, text, icons, screenshots or design from any other
  client application. All artwork and UI are original to Nautilarr.
- Do not name or compare to commercial client apps in code, comments, commit
  messages or docs. Refer to the *services* (Sonarr, qBittorrent, …) only as
  integration targets.

## Adding a new service integration

1. Create a new library target under `Packages/NautilarrKit/Sources/<Name>Kit`
   with its DTOs and a client that wraps the shared `APIClient`.
2. Reuse `RequestAuthorizer` for auth. For stateful schemes (cookie/session
   login), implement a new authorizer conforming to the protocol.
3. Add a `ServiceType` case and wire `authenticationKind`, `defaultPort`,
   `displayName` and `symbolName`.
4. Add **fixture-backed unit tests** (`Tests/<Name>KitTests`) using the
   `MockURLProtocol` pattern — no live servers in tests.
5. Make DTO fields tolerant: prefer optionals and lenient decoding so version
   differences don't break decoding.
6. If a field or endpoint is uncertain, verify it against the service's official
   API documentation and note `// VERIFY:` until confirmed.

## Code style

- Swift 5.9+, MVVM, `async/await`. Target **iOS 17 / macOS 14** (raised from
  iOS 16 / macOS 13 to use Citadel for SSH/SFTP). iOS 17 APIs are available.
- Anything that must compile on Mac Catalyst but not on iOS (or vice versa)
  goes behind `#if targetEnvironment(macCatalyst)`.
- No paid entitlements (push, App Groups, iCloud) and no paid dependencies.

## Before opening a PR

```bash
cd Packages/NautilarrKit && swift test
cd - && xcodegen generate
xcodebuild -project Nautilarr.xcodeproj -scheme Nautilarr \
  -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build
```

CI runs the package tests and builds the app for Mac Catalyst and the iOS
Simulator.
