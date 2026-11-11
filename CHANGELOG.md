# Changelog

All notable changes to this project will be documented in this file.

## 2.1.1 - 2026-11-11

### Fixed
- The app crashed at launch on macOS 15 ("Library not loaded: libswiftCompatibilitySpan.dylib"), in every release since 2.0.0. The library is part of macOS 26 and later but has to travel with the app on macOS 15, and it now does.
- A TV that went into standby while the app was connected kept showing as connected, on its input, with working-looking controls. The app now follows the TV's power state and lets the connection go when the TV reports standby, so the menu offers Turn On and Display Lock stops judging a picture nobody sees.

## 2.1.0 - 2026-11-11

### Added
- Panel Care now shows when the last pixel refresh ran, how many hours the TV has been used since, and roughly how much more use there is before the TV asks for the next one, alongside the TV's own schedule (a short refresh after every 4 hours of use on a C2). The app times the last refresh from when it first sees the TV's count go up, so these appear after the next refresh.
- Set hours for pixel refreshes: limit switching the TV off for a due refresh to part of the day, such as overnight. A Mac that is already locked when the hours begin is handled then. It still never happens while the Mac is in use.

### Fixed
- The TV was not turned back on when the Mac woke if it had gone into standby while the app was still connected to it. That state was taken for a pixel refresh in progress and left alone. Someone returning to the Mac now always gets the display back; only a wake with nobody there leaves a TV in standby untouched.
- A TV switched off for a pixel refresh was not brought back on unlock when "wake with Mac" was off. It always is now, since the app switched it off.
- Unlocking in the instant the TV was being switched off for a refresh could leave it off. The lock is checked again afterwards and the TV is woken.
- A TV caught part-way through switching off, or still off after a wake, was given up on. It is now sent a wake, and one more if the first is lost.
- A TV left in standby because nobody was at the Mac is woken as soon as someone is, without needing an unlock.
- Forgetting the TV now also forgets its pixel-refresh record.
- The diagnostic log could say the TV "did not run a pixel refresh" half a minute after it was switched off, while the refresh was still running. The outcome is now judged once the quiet period is over.

## 2.0.1 - 2026-11-11

### Fixed
- Panel Care showed a made-up "hours since the last pixel refresh" and could claim a refresh was long overdue when it was not. The TV's last-refresh figure is not on the same clock as its panel hours, so the pane now shows how many refreshes have run and whether the TV says one is due.
- Panel Care kept showing the state from before the TV was switched off, because the TV's shell is not ready the moment it powers on. The app now asks again shortly after connecting.
- A Mac that locked because its display went to sleep was not recognised as locked, so a due pixel refresh was not given room. macOS is now asked directly whether the session is locked.
- One unanswered keep-alive dropped and re-made the connection. It now takes two in a row.

### Added
- After the TV comes back from a pixel refresh quiet period, the diagnostic log records whether its refresh counter went up.

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
