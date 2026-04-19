# Platform Hygiene — SurVibe

> Conventions for code that varies by platform (iOS / iPadOS / macOS).
> Reviewers enforce these rules at PR time.

## Rule 1 — Platform folders

All `#if os(...)` / `#if targetEnvironment(...)` code lives under a `Platform/`
subfolder. Never inside feature code.

- App target: `SurVibe/Platform/`
- Each package: `Packages/SV*/Sources/SV*/Platform/`

## Rule 2 — Protocol borders

UIKit / AppKit interop crosses shared code only via a `public protocol` in SVCore.

```swift
// Packages/SVCore/Sources/SVCore/Platform/PlatformFileImporter.swift
public protocol PlatformFileImporter: Sendable {
    func presentImport() async throws -> URL
}
// SurVibe/Platform/iOSFileImporter.swift     (UIDocumentPickerViewController)
// SurVibe/Platform/macOSFileImporter.swift   (NSOpenPanel) — lands in SP-6
```

Feature modules never know whether they are running on iOS or macOS.

## Rule 3 — No platform-aware feature modules

`SVLearning`, `SVAudio`, `SVAI`, `SVSocial`, `SVBilling`, `SVAdvanced` must not
`#if os(macOS)`. If they need platform behavior, they depend on an SVCore
protocol.

## Rule 4 — Smallest island

`#if` blocks stay ≤ 15 lines. If larger, extract the body into a companion
file: `<Name>+iOS.swift`, `<Name>+macOS.swift`.

---

_Last updated: 2026-04-19. Landed as part of SP-0 Foundation._
