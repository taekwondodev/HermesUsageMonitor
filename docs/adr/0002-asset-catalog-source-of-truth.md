# ADR-0002: Use an Apple asset catalog as the visual resource source of truth

- Status: Accepted
- Date: 2026-08-18

## Context

The local app bundle currently generates an `.icns` icon from an SVG during packaging, while Xcode now contains a `Media.xcassets` catalog with an `AppIcon` set. Provider identity images are also currently stored as raw PNG/JPG resources.

Maintaining both a generator and an asset catalog creates two visual sources of truth and makes future asset changes easy to forget in one path.

## Decision

Use `Media.xcassets` as the single source of truth for the Finder app icon and provider identity assets. The packaging script compiles the catalog with Apple tooling into the main `.app` bundle. The old SVG-to-`.icns` generator is removed.

The provider images use catalog image sets named `OpenCodeGoIcon` and `ChatGPTIcon`. The supplied 1024×1024 Hermes icon is used as the source for every required macOS App Icon representation so the design remains identical at all scales.

Provider image sets use a single Universal appearance and preserve the supplied artwork. Raw duplicate image files and the old SVG generator are removed. If `actool` is unavailable, packaging fails rather than falling back to raw or generated assets.

The menu bar icon is a catalog image set named `HermesMenuBarIcon` derived from the same H-and-sparkle identity. It uses `template-rendering-intent` so the system recolors it, and the runtime loads it from the compiled `Assets.car` via `NSImage(named:)`, preserving aspect ratio at a menu-bar height of ≈15 pt. There is no programmatic generator and no SwiftUI fallback mark.

Its composition is a dominant robust outline H with one large four-point outline sparkle on the left. The sparkle shares the H height with clear optical separation; the H keeps robust bars and a long horizontal crossbar. The ring, colored background, gradients, glow, and secondary sparkle are intentionally omitted for menu bar legibility.


## Consequences

- Xcode and the packaging script use the same visual assets.
- Future provider/app visual resources are added to the catalog rather than copied into ad-hoc resource paths.
- The build requires the macOS `actool` toolchain already provided by Xcode.
- The main app bundle, not only the SwiftPM resource bundle, owns the compiled App Icon catalog output.
