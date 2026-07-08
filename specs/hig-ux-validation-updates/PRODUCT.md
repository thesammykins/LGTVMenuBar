# HIG UX Validation, Update Delivery, and webOS Compatibility

## Context

LGTV Menu Bar is intentionally a macOS menu bar utility. A July 2026 HIG review found that the compact status and quick-control surface generally fits the product, but the popover carries too much persistent settings and diagnostics work. The app also lacks a regular-window launch path, which makes accessibility auditing, screenshot capture, and UX validation harder than it needs to be.

No Figma mock exists for this work. The implementation should preserve the existing app identity and menu bar workflow while adding a dedicated validation surface and reducing HIG friction.

## Problems To Solve

1. Users need fewer hidden or surprising behaviors in critical actions.
2. Contributors need a reliable way to run the app as a normal macOS window for UX review, screenshots, and validation automation.
3. Destructive operations need confirmation before they erase configuration or diagnostic evidence.
4. Icon-only controls need accessible names and hover help.
5. Users need an in-app update path so every release does not require manually revisiting GitHub Releases.
6. LG webOS connection logic needs to keep handling newer TV firmware behavior, especially secure WebSocket requirements and payload shape drift.
7. The downloaded DMG should feel like a normal macOS drag-and-drop installer, not a raw folder dump.

## Desired User Experience

### Normal Menu Bar Build

- The app continues to launch as a menu-bar-only utility with no Dock icon.
- The menu bar popover remains focused on status, connection state, quick TV actions, volume, input, sound output, and a small settings entry point.
- Settings and diagnostics are available in a proper macOS settings-style surface rather than requiring a large persistent popover.
- Destructive actions ask for confirmation with a clear Cancel option.
- Failed quick actions show a concise user-visible error instead of failing silently.
- Icon-only controls are understandable to VoiceOver and pointer users.

### UX Testing Build

- A non-menu-bar variant can be launched locally as a regular macOS app window.
- The validation window exposes the same core UI surfaces that ship in the menu bar app.
- The validation variant must not require a real TV connection to inspect layout, accessibility labels, or screenshots.
- The validation variant must not mutate the user's real TV configuration unless explicitly launched in live mode.
- Screenshots and validation can be run from stable project-local scripts.

### Updates

- The app should support update checks through a standard macOS updater.
- Sparkle 2 is the preferred updater because it is maintained, supports Swift Package Manager, supports signed appcast feeds, and is the de facto update framework for directly distributed macOS apps.
- Release automation should publish or update an appcast feed from GitHub-hosted release artifacts.
- Users should be able to manually check for updates, and automatic update checks should respect user consent.
- The update feed should be served from this repository's GitHub Releases so users do not need a separate download location.

### DMG Installer

- The release DMG should open as a simple drag-and-drop installer.
- The `.app` icon should sit on the left and the Applications alias on the right.
- A simple generated background should visually reinforce the drag direction without adding explanatory copy.

### webOS Compatibility

- Newer TVs and firmware that reject insecure WebSocket connections should keep working through `wss://` port `3001`.
- Older TVs that still require `ws://` port `3000` should remain supported as fallback.
- The app should tolerate known response payload variation for volume, sound output, foreground app, and input information.
- Diagnostics should make unsupported or changed payloads visible without leaking unnecessary sensitive data.

## Invariants

- Normal menu-bar behavior remains the default release behavior.
- UX testing mode is opt-in and isolated from normal user state.
- Accessibility permission is only requested in response to an explicit user action.
- No secrets, signing keys, private update keys, or release credentials are committed.
- Existing Swift Testing coverage remains passing.
- Release DMGs remain signed and notarized through the existing release workflow.

## Acceptance Criteria

- `swift test` passes.
- A project-local run script can build and launch a regular-window UX testing variant.
- The UX testing variant can be used for screenshots without showing a menu bar item.
- Destructive settings actions require confirmation.
- Icon-only buttons have accessible labels and help text.
- Quick action errors are surfaced in the UI.
- Sparkle update checks are available from signed app builds.
- Release automation publishes an `appcast.xml` asset next to the DMG.
- The DMG has a styled Finder layout with app and Applications icons positioned for drag-and-drop installation.
- webOS endpoint selection and response parsing have targeted tests for secure WebSocket preference and newer payload variants.

## Deferred Or Follow-Up

- The first real update should be tested from one signed and notarized release build to a newer signed and notarized release build before announcing automatic updates broadly.
- GitHub Actions requires the `SPARKLE_ED_PRIVATE_KEY` secret to sign release appcasts. The matching public key is committed in `Info.plist`; the private key must remain outside source control.
- A complete visual regression suite can be layered on top of the UX testing window once the launch surface is stable.
