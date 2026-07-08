# Technical Plan

## Current Architecture

- `LGTVMenuBarApp` installs `AppDelegate` and currently provides an empty hidden `WindowGroup`.
- `AppDelegate` owns `TVController`, the `NSStatusItem`, and a custom `NSPopover`.
- `MenuBarView` and `SettingsView` are tightly coupled to concrete `TVController`.
- Release packaging is a SwiftPM executable wrapped into an `.app` by `scripts/build-dmg.sh`.
- There is no project-local regular-window run script or Codex Run action.

## Implementation Strategy

### 1. UX Testing Variant

Add a compile-time flag named `UX_TESTING_APP`.

When `UX_TESTING_APP` is enabled:

- `AppDelegate` should set `NSApp` activation policy to `.regular`.
- It should skip status item and popover setup.
- It should open a normal `NSWindow` containing a dedicated UX validation root view.
- It should skip onboarding and startup auto-connect.
- It should seed the controller with in-memory fixture state or a controlled sample configuration in a separate test mode path, not normal user defaults.

Because `TVController` normally persists through `UserDefaults.standard` and exposes most UI state as `private(set)`, the implementation keeps fixture behavior narrow:

- Launch a window that renders the actual menu bar content and settings surfaces.
- Seed sample state through a `UX_TESTING_APP`-only controller helper without writing user defaults.
- Avoid connecting to a real TV automatically.
- Treat deeper state-fixture refactoring as follow-up if it would require broad protocolizing of every view.

Add:

- `Sources/LGTVMenuBar/Views/UXTestingRootView.swift`
- `script/build_and_run.sh`
- `.codex/environments/environment.toml`

The run script should:

- stop only an existing `LGTVMenuBarUXTesting` process,
- build with `swift build -Xswiftc -D -Xswiftc UX_TESTING_APP`,
- stage a local `.app` bundle under `dist/UXTesting/LGTVMenuBarUXTesting.app`,
- launch it with `/usr/bin/open -n`,
- support `--verify`, `--logs`, and `--screenshot`.

### 2. HIG And Accessibility Fixes

Focus on changes with high confidence and low product risk:

- Add confirmation dialogs for clearing TV configuration and clearing diagnostic logs.
- Add `.accessibilityLabel` and `.help` to image-only quick controls.
- Replace hard-coded onboarding blue where practical with `.tint` / `.accentColor`.
- Surface quick-action errors through a small alert or inline error row in `MenuBarView`.
- Keep the normal menu-bar popover compact and open a dedicated settings window from the gear action.

### 3. Sparkle Update Path

Use Sparkle 2 for directly distributed updates.

Implemented pieces:

- `Package.swift` depends on Sparkle 2.9.x through SwiftPM.
- `SoftwareUpdateController` owns `SPUStandardUpdaterController` and only starts Sparkle when the app bundle has `SUFeedURL` and `SUPublicEDKey`.
- The General settings tab exposes `Check for Updates...` and `Automatically check for updates`.
- `Info.plist` points `SUFeedURL` at `https://github.com/thesammykins/LGTVMenuBar/releases/latest/download/appcast.xml`.
- `Info.plist` commits the public EdDSA key only. The private key is not stored in the repo.
- `scripts/build-dmg.sh` embeds `Sparkle.framework` into `Contents/Frameworks` and signs nested frameworks before signing the app.
- `script/build_and_run.sh` stages the same framework for the UX testing app bundle while keeping Sparkle disabled in `UX_TESTING_APP`.
- `scripts/generate-appcast.sh` runs Sparkle's `generate_appcast` from SwiftPM artifacts and writes `release/appcast.xml`.
- `.github/workflows/build.yml` generates the appcast after notarization and uploads it next to the DMG as both a workflow artifact and a GitHub Release asset.

Key handling:

- The local Sparkle key account is `com.thesammykins.lgtvmenubar`.
- Local appcast generation can use that Keychain account without exporting the private key.
- GitHub Actions expects `SPARKLE_ED_PRIVATE_KEY` when publishing releases.
- Do not commit the Sparkle EdDSA private key, Developer ID certificate material, App Store Connect notarization credentials, or temporary key exports.

Remaining release validation:

- Test an update from one signed and notarized release build to a newer signed and notarized release build before announcing automatic updates broadly.

### 4. webOS Compatibility

Current code already tries SSL first (`wss://:3001`) and falls back to non-SSL (`ws://:3000`), matching known firmware changes where insecure WebSocket connections are rejected. Strengthen this by:

- Extracting WebSocket endpoint selection into a small testable type.
- Adding tests that SSL is preferred and non-SSL remains available.
- Adding tests for payload shape variants in foreground app, input, volume, and sound output parsing.
- Avoiding model-year-only assumptions when a live TV answers only one protocol.
- Logging protocol choice in diagnostics without exposing secrets.

Implemented pieces:

- `WebOSConnectionEndpoint` owns secure-first endpoint ordering.
- `WebOSConnectionEndpointTests` covers `wss://:3001` preference and `ws://:3000` fallback metadata.
- `WebOSClientTests` covers nested foreground app, volume, and sound-output payload variants.

### 5. Styled DMG Installer

Implemented pieces:

- `scripts/assets/dmg-background.png` contains the generated installer background.
- `scripts/build-dmg.sh` now creates a read/write staging image, mounts it, applies Finder icon-view metadata, and converts it to the final compressed DMG.
- The app icon is positioned over the left TV target and the Applications symlink is positioned inside the right dashed target.
- The build script adds `@executable_path/../Frameworks` to the staged app binary if needed before signing, so embedded Sparkle can load from the app bundle.
- `bless --openfolder` is best-effort because it is unsupported on this Apple Silicon host.

Validation:

- Mount the final DMG and inspect the Finder window before release.
- The July 8, 2026 preview confirmed the `.app` and Applications icons align with the generated background targets.

### 6. Dead Code And Refactoring

- Remove unused `StatusItemIconManager` only if it remains unused after accessibility/status updates.
- Prefer small helper types over broad rewrites.
- Avoid protocolizing the entire UI layer unless needed for fixture-backed validation.

## Validation Plan

- `swift build`
- `swift test`
- `./script/build_and_run.sh --verify`
- `./script/build_and_run.sh --screenshot`
- `./scripts/build-dmg.sh --skip-signing`
- `./scripts/generate-appcast.sh`
- Manual screenshot review of the generated UX testing window.
- Manual Finder preview of the generated DMG installer window.

## Risks

- SwiftPM GUI app bundling can hide framework embedding issues if Sparkle is added prematurely.
- Running the normal app during tests could modify user defaults or try to connect to a real TV.
- Accessibility and screenshot automation may need additional permissions on macOS.
- webOS behavior is partly de facto rather than fully documented by LG, so compatibility changes should be diagnosis-friendly and conservative.
