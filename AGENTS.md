# AGENTS.md - LGTVMenuBar

A macOS menu bar app that controls an LG webOS TV used as a Mac display: power, input, volume,
sleep/wake automation, optional root-shell features, and Display Lock.

- Platform: macOS 15+, Swift 6 with strict concurrency, SwiftUI hosted from AppKit.
- Tests: Swift Testing (`@Suite`, `@Test`, `#expect`). No XCTest.
- Dependencies: Sparkle 2 (updates), Citadel pinned to exactly 0.12.0 (SSH; see `Package.swift` for why).

Read `docs/ARCHITECTURE.md` before changing anything under `Services/` or `Policies/`.

## Commands

```bash
swift build
swift test                                   # all tests, about 30 s
swift test --filter "PowerPolicy|ActionGovernor"   # regex over suite and test names
./script/build_and_run.sh --snapshots        # render every view to screenshots/snapshots/*.png
./scripts/build-dmg.sh --disable-updater     # local test build into release/
```

There is no linter; compiler warnings are the gate. Fix new warnings you introduce.

## Looking at the UI

You cannot see the menu bar, and `--screenshot` needs Screen Recording and Accessibility
permission that an agent shell usually lacks. Use `--snapshots` instead: it draws the popover
and each Settings pane inside the app, in light and dark, across the scenarios in
`TVController.UXScenario`, and writes PNGs you can open with the Read tool. Add a scenario there
when you add a UI state.

## Testing without a TV

Nearly everything is testable offline. Use these rather than adding hooks to production code.

| Need | Use |
| --- | --- |
| Real WebSocket behaviour (silence, slow pairing, refusal, drops, rejected or unanswered commands) | `Tests/.../Support/FakeTV.swift` with `WebOSClient(endpoints:timeouts:)` |
| Controller logic | `MockWebOSClient`, `MockWOLService`, `MockPowerManager`, `StubReachabilityProbe` |
| Root shell | `FakeRootShell` (scripted), `FakeTelnetServer` (loopback) |
| Display Lock | `FakeDisplayService` and `FakeLockTV` in `DisplayLockTests.swift` |

The whole target runs in parallel on the main actor and some suites hold it for seconds. In a
test, wait on a condition by polling a bounded number of times, not against a wall-clock deadline.

## Rules that are easy to break

1. **Automation must not loop.** Anything automatic that changes the TV or the Mac's display
   goes through `TVController.permitAutomaticAction` (the `ActionGovernor`). User-initiated
   actions do not.
2. **Never disturb a TV someone else is using.** Power-off and input switching depend on
   `TVForeground` and on whether the app itself powered the TV on. The rules live in
   `PowerPolicy` and each has a test; change the policy and its test together.
3. **Never prompt the TV in a loop.** Automatic paths call `connectAutomatically()`, which
   refuses while `pairingRequiresUser` is set. Only `connect()` (a user action) clears it.
4. **A request is not done until the TV confirms it.** `sendCommand` and `request` wait for the
   reply and throw on rejection or silence. Do not set local state before they return.
5. **Timeouts must hold without cancellation.** Callback APIs ignore task cancellation. Drive
   timeouts with a timer that resumes the continuation (see `WebOSClient.perform`, `withDeadline`).
   A task-group timeout around a continuation hangs; that bug shipped in 1.6.
6. **Secrets live in the Keychain only**, never in `TVConfiguration`, UserDefaults or logs.
7. **Root is optional.** Every root-backed feature needs a non-root path or a clear "unavailable".
8. **Settings apply as they change.** Write through `controller.updateConfiguration { $0.x = y }`
   or `configurationBinding`. Do not rebuild `TVConfiguration` memberwise in a view.
9. **A pixel refresh never takes the display from someone using the Mac.** The TV is only
   switched off for one while the Mac is locked or asleep; there is no manual trigger. While
   `pixelRefreshStartedAt` is set, nothing reconnects and unattended wakes wait
   (`PanelCarePolicy`). Unlocking, opening the menu or recent input always wins.
10. **Log decisions.** Every automation decision records its inputs through `logDiagnostic`; that
   log is how problems on real hardware get diagnosed.

## Conventions

- Models are structs; services are `final class`; UI-facing state is `@MainActor @Observable`.
- Protocols go in `Protocols/` with a `Protocol` suffix when a mock exists for them.
- Pure decision logic goes in `Policies/` as enums or structs with no I/O.
- Errors are domain enums with `LocalizedError`; the description is shown to users as written.
- Comments explain why. Document any `@unchecked Sendable` or `nonisolated(unsafe)` where it is used.
- Liquid Glass: the popover and the Settings toolbar are the system's glass. Views inside them
  use standard controls and add no materials, backgrounds or `.glass` button styles (that would
  be glass on glass). At most one tinted (`.borderedProminent`) control per state.
- UI copy: sentence case for labels and toggles, title case for buttons and section headers,
  "…" not "...", explanations in section footers (`SectionFooter`), results inline
  (`InlineNotice`) rather than in alerts.

## Unverified on hardware

Some behaviour was written from documentation and could not be tried against a TV. The list,
with how to check each item, is in `docs/HARDWARE-VALIDATION.md`. Keep it current: remove an
item when it is confirmed, add one when you write code you could not exercise.

## Releasing and local installs

See `docs/RELEASING.md`. Short version: bump `CFBundleVersion` and
`CFBundleShortVersionString` in `Sources/LGTVMenuBar/Info.plist`, complete the `CHANGELOG.md`
section, validate with the branch workflow, then tag `vX.Y.Z`. Samantha's own install is
`./scripts/build-dmg.sh --disable-updater` copied to `/Applications`.

`Package.swift` defines `LOCAL_ARYLIC_BUILD`; Arylic code is guarded by it and tests must pass
with it set.
