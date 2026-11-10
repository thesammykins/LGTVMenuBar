# Changelog

All notable changes to this project will be documented in this file.

## 2.0.0 - 2026-11-10

### Added
- Display Lock: hold the Mac's resolution, refresh rate and HDR, and optionally the TV's PC input label and picture mode, while the TV shows the Mac's input. It does nothing on any other input or TV app, and pauses itself rather than loop if a setting will not stay set.
- Rooted TV support: optional SSH or Telnet access to a TV rooted with Homebrew Channel. The app creates its own SSH key, keeps it in the Keychain, pins the TV's host key and reports what the shell offers.
- Panel Care (rooted TVs): shows the OLED panel's hours and how long since its last pixel refresh, and can switch the TV off for a due refresh while the Mac is locked or asleep, leaving it undisturbed until it finishes or someone returns.
- Automatic reconnect after the connection drops, without waking the TV.
- A loop guard for automation: more than six automatic wakes, power-offs, input switches or setting changes in ten minutes pauses that kind of automation and says so in the menu.
- "Also when opening the menu" setting for waking the TV.
- Settings now shows the TV's model, software and firmware, and uses the TV's own input names.
- Right-click the menu bar icon for Settings and Quit; Command-comma opens Settings.

### Changed
- Settings is a standard Mac settings window with TV, Automation, Display, Panel Care, General and Advanced panes. Changes apply as you make them; there are no Save buttons.
- Mac sleep only turns the TV off while it shows the Mac's input. A TV on another input or showing a streaming app is left on.
- The input is no longer switched when the app reconnects to a TV that was already on.
- Commands wait for the TV to confirm them, so a rejected command is reported instead of silently ignored.
- Activating the app no longer turns the TV on.
- Missing Accessibility permission no longer switches the volume-keys setting off.
- Results and errors appear in place instead of in alerts, with the reason for a failed connection.

### Fixed
- Connecting to a TV that accepted the connection but never answered could hang until the app was relaunched, blocking all later wake attempts.
- A pairing prompt accepted after ten seconds connected and was then dropped.
- A declined pairing prompt could reappear on the TV repeatedly.
- The PC input label was never applied on current firmware: the TV refused the request and the app ignored the refusal. It now goes through the root shell, or the TV's notification service without root.
- The input list was requested from an endpoint that does not exist on current firmware, so the app never knew which input was labelled a PC.
- An input the app did not recognise was reported as HDMI 1.
- Mac sleep did not cancel a wake that was still retrying.

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
