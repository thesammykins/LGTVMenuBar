# AGENTS.md - LGTVMenuBar

## Project Snapshot
- **Platform**: macOS 15+
- **Language**: Swift 6.x with strict concurrency
- **UI**: SwiftUI menu bar app
- **Tests**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)
- **Packaging**: DMG via `scripts/build-dmg.sh`

## Build, Test, Lint
```bash
# Build
swift build

# Run all tests
swift test

# Run a suite or single test (SwiftPM filter regex)
swift test --filter TVConfigurationTests
swift test --filter "initWithAllProperties"

# List tests (useful for filter patterns)
swift test --list-tests
```

Notes:
- `swift test --filter` accepts `<test-target>.<test-case>` or `<test-target>.<test-case>/<test>`.
- No explicit lint tool in this repo; compiler warnings/errors are the gate.

## DMG Build (Release Packaging)
```bash
# Build a universal (arm64 + x86_64) development DMG (ad-hoc signing)
./scripts/build-dmg.sh

# Clean build + DMG
./scripts/build-dmg.sh --clean

# Build a locally signed release without notarization
./scripts/build-dmg.sh --local-release

# Build a signed and notarized release
./scripts/build-dmg.sh --release

# Build a local-only app/DMG with Sparkle updater metadata removed
./scripts/build-dmg.sh --disable-updater
```

Operational notes:
- The default DMG script path performs ad-hoc signing; Accessibility permission must be re-granted after each ad-hoc build.
- `--local-release` signs with a local `Developer ID Application` certificate but does not notarize.
- `--release` requires a local `Developer ID Application` certificate plus notary credentials via `ASC_KEY_FILE`/`ASC_KEY_ID`/`ASC_ISSUER_ID` or a configured `ASC_1PASSWORD_ITEM`.
- `--disable-updater` removes `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, and `SUAutomaticallyUpdate` from the staged app bundle. Use this for local/private builds that should not self-update.
- The DMG script embeds `Sparkle.framework`, ensures the app binary has `@executable_path/../Frameworks`, and applies the Finder drag-to-Applications layout with `scripts/assets/dmg-background.png`.
- The DMG Finder layout intentionally places `LGTVMenuBar.app` on the left TV target and the Applications symlink on the right dashed target; preview the mounted DMG when changing `scripts/build-dmg.sh` or `scripts/assets/dmg-background.png`.
- GitHub Actions release validation expects `ASC_CERTIFICATE`, `ASC_CERTIFICATE_PASSWORD`, `ASC_PRIVATE_KEY`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `SPARKLE_ED_PRIVATE_KEY` repo secrets.
- Tag releases extract their GitHub Release body from the matching `CHANGELOG.md` version section into `release/release-notes.md`; keep the changelog entry complete before tagging.
- When duplicate `Developer ID Application` subject names exist in Keychain after certificate rotation, resolve the certificate by SHA-1 identity hash before calling `codesign`; subject-name signing becomes ambiguous.
- `xcrun stapler validate` is the reliable local notarization check for this DMG flow; `spctl` can report `source=Insufficient Context` on a freshly stapled local DMG even when notarization succeeded.
- Release artifacts are written to `release/`; branch workflow runs upload `release/*.dmg` plus `release/appcast.xml`, while tag runs also publish them to GitHub Releases.

## Sparkle Updates
```bash
# Generate or refresh appcast.xml after building the release DMG
./scripts/generate-appcast.sh
```

Notes:
- Sparkle 2 is integrated through SwiftPM. Keep `Package.resolved` committed so CI resolves the same Sparkle version family.
- `Sources/LGTVMenuBar/Info.plist` contains the public Sparkle feed URL and EdDSA public key for distributable builds.
- `SoftwareUpdateController` starts Sparkle only when both `SUFeedURL` and `SUPublicEDKey` exist in the app bundle. UX-testing and `--disable-updater` builds omit those keys, so the updater remains inactive.
- `scripts/generate-appcast.sh` signs the appcast using `SPARKLE_ED_PRIVATE_KEY`, `SPARKLE_PRIVATE_KEY_FILE`, or the local Keychain account `com.thesammykins.lgtvmenubar`. Never print or commit the private key.
- The appcast feed URL currently targets `https://github.com/thesammykins/LGTVMenuBar/releases/latest/download/appcast.xml`.
- For a branch validation build, run `gh workflow run "Build and Release" --ref <branch> -f version=X.Y.Z`; this uploads build artifacts but only tag refs create a GitHub Release.

## UX Testing App
```bash
# Build and open the non-menu bar validation app
./script/build_and_run.sh

# Build, open, verify a window appears, then exit
./script/build_and_run.sh --verify

# Build, capture a validation screenshot, then exit
./script/build_and_run.sh --screenshot
```

Notes:
- The UX-testing app uses `UX_TESTING_APP` and `UXTestingRootView` to show a normal macOS window instead of only the menu bar extra.
- The runner creates `dist/UXTesting/LGTVMenuBarUXTesting.app` and writes screenshots to `screenshots/`; both paths are ignored.
- The UX-testing bundle has a separate bundle id (`com.thesammykins.lgtvmenubar.ux-testing`) and no Sparkle feed metadata.
- `--verify` and `--screenshot` should not leave `LGTVMenuBarUXTesting` running. If interrupted, close only that process and do not kill a user-running production app.

## LG webOS Compatibility
- WebOS connection attempts should prefer secure WebSocket `wss://<host>:3001` and fall back to insecure `ws://<host>:3000`.
- Keep endpoint ordering centralized in `WebOSConnectionEndpoint.preferredEndpoints(for:)`; tests live in `WebOSConnectionEndpointTests`.
- Pairing registration is intentionally single-flight: duplicate `TVController.connect()` calls should join the active task, and `WebOSClient.connect(...)` must treat `.registering` as an active transition instead of resetting the socket. Coverage lives in `TVControllerConnectionTests` and `WebOSClientTests`.
- Wake/menu reconnect retries must not call `disconnect()` while `webOSClient.connectionState.isTransitioning`; preserve active registration and let the retry window continue. Ignore stale queued WebOS state callbacks that no longer match the client state.
- Newer webOS command payload shapes should be covered in `WebOSClientTests` before changing command serialization.
- Wake reliability changes should keep coverage in `TVControllerWakeTests`; avoid restoring fixed retry-count behavior that exits before the wake window completes.

## Local Arylic Builds
- `Package.swift` currently defines `LOCAL_ARYLIC_BUILD` for the app and test targets.
- Arylic-only code is guarded with `#if LOCAL_ARYLIC_BUILD`; keep tests passing with that flag enabled.
- For Samantha's local install, build with `./scripts/build-dmg.sh --disable-updater`, then install `release/LGTVMenuBar.app` into `/Applications/LGTVMenuBar.app`. Verify updater keys are absent from `/Applications/LGTVMenuBar.app/Contents/Info.plist`.

## Versioning & Release Process
When pushing a new build:

1. **Update Info.plist** (`Sources/LGTVMenuBar/Info.plist`):
   - Increment `CFBundleVersion` (build number) by 1.
   - Update `CFBundleShortVersionString` (semver: MAJOR.MINOR.PATCH).
     - PATCH: bug fixes, minor changes
     - MINOR: new features, non-breaking changes
     - MAJOR: breaking changes

2. **Validate the release workflow on the branch**:
   ```bash
   git push -u origin <branch>
   gh workflow run "Build and Release" --ref <branch> -f version=X.Y.Z
   gh run watch
   ```

3. **Commit version changes**:
   ```bash
   git add Sources/LGTVMenuBar/Info.plist
   git commit -m "chore: bump version to X.Y.Z (build N)"
   ```

4. **Create and push git tag**:
   ```bash
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```

5. **Verify GitHub Actions workflow** triggers for the new tag (DMG build + notarized release)

Example:
```bash
# Bump from 1.1.2 (build 8) to 1.1.3 (build 9) for a bugfix
# Edit Info.plist: CFBundleVersion=9, CFBundleShortVersionString=1.1.3
git add Sources/LGTVMenuBar/Info.plist
git commit -m "chore: bump version to 1.1.3 (build 9)"
git tag v1.1.3
git push origin main
git push origin v1.1.3
```

## Code Style & Conventions

Imports:
- Order: Foundation first, then system frameworks (e.g., OSLog, Observation), then local modules.

Formatting:
- Use `// MARK: -` to segment major sections.
- Keep property/documentation blocks grouped and consistent.
- Favor clear, self-documenting names over comments.

Types & Access:
- Use `struct` for models/value types.
- Use `final class` for services/controllers.
- Use `public` for shared protocols/models.
- Keep mutable state `private(set)` unless mutation is required externally.

Protocols:
- Place in `Sources/LGTVMenuBar/Protocols/`.
- Suffix with `Protocol` and mark `Sendable` when used across concurrency boundaries.

Naming:
- Types: PascalCase.
- Properties/methods: camelCase.
- Tests: descriptive names that read like behavior.

Errors:
- Use domain-specific enums conforming to `Error`, `Equatable`, `LocalizedError`.
- Prefer user-facing `errorDescription` strings for UI/diagnostics.

Concurrency:
- Use `async/await` and structured concurrency.
- Use `@MainActor` for UI-bound state/services.
- Use `CheckedContinuation` for callback bridging.
- Use `Task.sleep` for async delays.

Tests & Mocks:
- Use Swift Testing (`import Testing`).
- Group tests with `@Suite`, name tests with `@Test("...")`.
- Use `#expect` for assertions.
- Mocks live in `Tests/LGTVMenuBarTests/Mocks/` with `Mock` prefix.
- Include `reset()` methods in mocks to clear captured state.

Documentation:
- Use `///` doc comments for public APIs.
- Avoid excess comments; explain WHY when behavior is non-obvious.

## Cursor / Copilot Rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found in this repo.

## Verification Checklist
```bash
swift build
swift test
swift test --filter TVConfigurationTests
./script/build_and_run.sh --verify
./scripts/build-dmg.sh --skip-signing
./scripts/generate-appcast.sh
./scripts/build-dmg.sh --disable-updater
```
