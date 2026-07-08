# Changelog

All notable changes to this project will be documented in this file.

## 1.6.2 - 2026-07-08

### Fixed
- Wake/menu reconnect no longer disconnects an active webOS registration handshake after a failed retry.
- Stale queued WebOS connection callbacks are ignored when the client has already moved to a newer state.

## 1.6.1 - 2026-07-08

### Fixed
- Pairing and reconnect reliability now preserves an in-flight webOS registration handshake instead of restarting the socket when duplicate connect requests arrive.

### Changed
- GitHub Releases now use the matching `CHANGELOG.md` section for release notes.

## 1.6.0 - 2026-07-08

### Added
- Sparkle 2 updater integration with signed GitHub release appcasts.
- Styled drag-to-Applications DMG artwork and Finder layout.
- Non-menu bar UX validation app with scripted verify and screenshot modes.
- Secure-first webOS connection endpoint handling for newer LG TV firmware.

### Fixed
- Settings, onboarding, menu, and confirmation flows now better match macOS HIG expectations.
- Wake recovery no longer exits early on newer webOS connection timing.

### Changed
- Release workflow now uploads DMG and `appcast.xml` artifacts, and tag builds publish both to GitHub Releases.
- Local Arylic builds can be packaged with updater metadata disabled.

## 1.2.0 - 2026-02-02

### Added
- Diagnostics: “Gather Device Details” button to capture raw WebOS payloads.
- Diagnostics: periodic device status snapshots when debug logging is enabled.
- README: clickable screenshots with layout and captions.

### Fixed
- Accessibility/media key control gating and reinitialization on app activation.
- Auto-connect when opening the menu bar popover.
- Input/sound output parsing and stability (prevents flicker to Unknown).
- Sound output mapping for headphone and related variants.

### Changed
- Version bumped to 1.2.0 (build 10).
