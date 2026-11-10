# Refresh audit and plan: reliability, HIG, rooted TVs, Display Lock

Date: 2026-11-10. Baseline: `main` at `32f15ca` (v1.6.2, build 17).
Status: implemented on `feat/reliability-root-display-lock` as 2.0.0. This file records the audit that
motivated the work; `docs/ARCHITECTURE.md` describes the result and `docs/HARDWARE-VALIDATION.md`
lists what still needs checking on a TV. The plan in section 5 was delivered as one release.

## Baseline

- `swift build` and `swift test` pass: 369 tests in 23 suites (Swift 6.4, Xcode 27, macOS 27.2).
- Two findings below were reproduced with a throwaway probe against a local fake TV; the probe
  was removed afterwards. Everything else is from reading the code and is marked as such.
- The sibling folder `~/Development/lg_tv_macos` (Swift + Python backend scaffold) has no Swift
  code and no commits. It is not the shipped app and was not used.

## 1. State machines as they exist today

None of these is modelled as a state machine. Each is a set of flags and tasks.

| Machine | Where | How it is held |
|---|---|---|
| Connection | `WebOSClient._connectionState` and `TVController.connectionState` | Two copies of a 5-case enum, kept in step by `applyWebOSConnectionState` / `syncConnectionStateFromWebOSClient`, plus `handshakeCompleted`, `connectionAttemptID`, `connectTask` |
| Wake recovery | `TVController.ensureTVAwake` | `isWakeInProgress`, `isWakeRecoveryQueued`, `wakeRecoveryTask`, a private `ScreenRecoveryOutcome` |
| Sleep | `TVController.handleMacSleep` | `lastSleepExecution` debounce timestamp |
| TV power | `TVPowerStatus.normalizedState` | Queried on demand, never subscribed |
| Diagnostics capture | `TVController` | `diagnosticCaptureUntil`, restore tuple, `Timer` |
| Media key capture | `updateMediaKeyCapture` | Re-evaluated from a `didSet` on every connection change |

## 2. Reliability findings

Severity is user impact. "Reproduced" means observed, "Read" means from code only.

### High

1. **Connecting to a TV that accepts the socket but never answers hangs forever.** Reproduced:
   `connect()` was still pending at 35 s with the client in `Registering`; it only returned when
   `disconnect()` was called. The 10 s `withTimeout` (`WebOSClient.swift:256`) cannot cancel
   `performHandshake`, because the handshake waits on a continuation that ignores cancellation,
   and a task group waits for all children. Consequences (read): `connectTask` never clears, every
   later `connect()` joins the hung task, `isWakeInProgress` stays true, and all later wake
   recoveries are ignored until relaunch. The same flaw means a pairing prompt accepted after 10 s
   registers successfully and is then torn down by the late timeout error (`WebOSClient.swift:206-212`).
2. **Opening the menu, or activating the app, can power the TV on and switch its input.**
   `AppDelegate.swift:235-239` and `:94-100` call `ensureTVAwake`, which sends Wake-on-LAN when
   disconnected. Read.
3. **Input hijack.** When the app reconnects to a TV that is already on, `ensureTVAwake` falls
   through to `performPostWakeActions` (`TVController.swift:422-427`) and switches to the preferred
   input even if someone is watching another one. The sleep path deliberately leaves such a TV
   alone and disconnects, which sets this up for the next Mac wake. Read.
4. **"Current input" is not the current input.** `mapAppIdToInputType` ignores non-input apps, so
   after switching to Netflix or live TV `currentInput` still says HDMI 1, and Mac sleep powers the
   TV off mid-programme. `mapInputSourceToType` also maps every unknown source to HDMI 1
   (`WebOSClient.swift:975`). Read.
5. **No reconnect after a dropped socket.** A transport failure moves to `.error` and stays there
   until the menu is opened or the Mac wakes. While in `.error`, sleep-with-Mac cannot power the TV
   off because `sendCommand` refuses. There is no keepalive ping, so a half-open socket is only
   noticed on the next send. Read.

### Medium

6. **Commands are fire-and-forget.** `sendCommand` succeeds when the frame is written. Only
   `getPowerState` is correlated to its response; `returnValue: false`, `type: "error"` (pairing
   denied, 401) and every other reply are matched by guessing at payload keys. `switchInput`,
   `toggleMute`, `setSoundOutput` update local state optimistically. Display Lock cannot be built
   on this.
7. **`capabilities` is never populated.** The only call to `capabilityCallback` is in
   `handleForegroundAppUpdate` (`WebOSClient.swift:760`), which nothing calls. So
   `capabilities?.inputIcons = …` is a no-op, PC-mode detection always reads "not PC", and
   `setDeviceInfo` is re-sent on every wake. Read; 369 green tests do not cover it.
8. **Stale `defer` can clear a newer connect task** (`TVController.swift:299-300` after
   `disconnect()` + reconnect). Read.
9. **Mac sleep does not cancel an in-flight wake recovery**, and a wake during a slow power-off is
   not coordinated with it. Read.
10. **A missing Accessibility grant permanently turns the user's media-key preference off**
    (`TVController.swift:1108-1112`), which bites after every ad-hoc build. Read.
11. **Pairing denial is not handled**; the user waits for a timeout, and retry loops can re-raise
    the prompt on the TV. Read.

### Low

- Dead code: `handleForegroundAppUpdate`, `handleInputChange`, `PowerManager.isSystemSleeping`
  (returns a made-up value), prevent/allow sleep (unused), `dismissPopover` environment value.
- `ConnectionState.error` compares equal regardless of error, so changed errors are not logged.
- Logger subsystem `com.lgtvmenubar` differs from the bundle id.
- TLS trust accepts any certificate from any host; pin the TV's certificate on first pairing.
- Test hooks (`setTestSendCommandHandler` etc.) live in the production client.

## 3. UI and HIG findings (summary)

Full list with line references came from a separate read-only audit; the points that drive work:

- Settings is a hand-built `NSWindow` with an in-content `TabView`: no `Settings` scene, no
  Cmd-comma, no toolbar panes, size set twice.
- Text fields render their placeholder as the label (`SettingsView.swift:85`).
- Mixed save model: TV and Automation need Save and drop edits silently on tab switch; General
  applies immediately. Errors are swallowed with `try?`. IP and MAC are only checked non-empty.
- Error and empty states carry no detail and no action; informational alerts are used for
  "Saved" and "Copied".
- VoiceOver: the volume slider exposes curve position, menus are unnamed, status is colour-only.
- `TVConfiguration` is rebuilt memberwise in three views, so every new field must be threaded
  through all three or it resets. This blocks adding root and Display Lock settings cleanly.
- Input lists come from `TVInputType.allCases`, not from the TV.
- `VolumeCurveTests` tests a copy of the curve, not the shipping code.
- README describes onboarding steps that do not exist.

## 4. Research status

- **Root access on the TV** (partly verified, see sources): Homebrew Channel provides SSH as
  `root` with public-key auth, a default password until `/home/root/.ssh/authorized_keys` exists,
  and optional unauthenticated Telnet. Port numbers differ between guides (22 vs 9922 for the
  Developer Mode jail); to be confirmed on the real TV.
- **Extra data with root** (unverified): `luna-send` to `com.webos.settingsservice`
  `getSystemSettings` / `setSystemSettings` (picture, other, option categories) and video-signal
  services. Exact keys and whether any are reachable without root over SSAP need capturing from
  the C2. A dedicated research pass on this was started and failed part-way; it has not been redone.
- **macOS side**: resolution and refresh rate use public CoreGraphics. No public API toggles HDR;
  no open-source use of the private call was found, and private display APIs reportedly broke in
  macOS 26.3. HDR enforcement is therefore the riskiest part of Display Lock and needs a spike.
- **Which firmware is rootable** is out of scope for the app: it only needs to talk to a TV the
  owner has already rooted.

Sources: [webos-homebrew-channel](https://github.com/webosbrew/webos-homebrew-channel),
[webosbrew SDK configuration](https://www.webosbrew.org/pages/sdk-configuration),
[webosbrew hidden system settings](https://www.webosbrew.org/pages/hidden-system-settings),
[bscpylgtv](https://github.com/chros73/bscpylgtv),
[Home Assistant picture-mode thread](https://community.home-assistant.io/t/lg-webos-change-picture-setting-mode-with-scripts/262915),
[webosbrew rooting](https://webosbrew.org/rooting),
[OpenDisplay release note](https://newreleases.io/project/github/aquitaine/OpenDisplay/release/v0.8.0).

## 5. Plan

Each phase is shippable on its own and mock-first. Hardware checks come last in each phase.

### Phase 1 - Reliability core (release as 1.7.0)

- `SSAPSession`: one request/response layer with ids, per-request timeouts that really cancel,
  `error` frames, subscriptions, and a ping keepalive. Replaces duck-typed payload sniffing.
- `ConnectionMachine`: a pure reducer (state, event) -> (state, effects) owned in one place;
  the controller observes it instead of mirroring it. States: idle, connecting, awaitingPairing,
  connected, backingOff(attempt), suspended (Mac asleep), failed(reason).
- `PowerCoordinator`: one reducer for Mac sleep/wake/unlock/menu events and TV power state, so
  sleep cancels wake and the reverse.
- `ActionGovernor`: a shared budget for anything that changes the TV (power, input, settings):
  at most N actions per window, exponential backoff, then a tripped state shown in the UI with a
  manual reset. This is the loop guard for wake storms now and Display Lock later.
- Fix findings 1-11. Model the foreground as `input(x) | app(id) | unknown`; take the input list
  from the TV. Only switch input when the app itself powered the TV on. Menu open reconnects
  but does not wake unless a new setting allows it.
- `FakeTV`: an in-process scripted SSAP server (silent socket, slow pairing, denial, drop,
  foreground changes, power states) used by tests instead of client test hooks.
- Every reducer transition and every governor rule gets a test.

### Phase 2 - Settings and HIG (1.8.0)

- `Settings` scene with toolbar panes: TV, Automation, Display, General, Advanced. Cmd-comma,
  restored pane, right-click status menu with Settings and Quit.
- Apply-on-change with inline validation; one `TVConfiguration` mutation path on the controller.
- Shared `ConnectionStatusView` with error detail, progress and a primary action for each state.
- Labelled pickers, slider accessibility value, 20 pt targets, section footers instead of
  tooltips, sentence-case pass, string catalog, previews, more UX-harness states.

### Phase 3 - Rooted TV support (1.9.0)

- Advanced pane: "My TV is rooted" toggle; transport (SSH or Telnet); host defaulting to the TV's
  IP with an explicit override; port following the transport; username; key file or password in
  the Keychain; Test Connection; capability readout. Telnet carries a plain warning.
- `RootShell` protocol with `SSHRootShell`, `TelnetRootShell`, `FakeRootShell`. Host identity is
  checked against the paired TV before any command runs.
- `RootCapabilities` probe (read-only) feeding richer status: signal format, picture mode, power
  detail. Root is always optional; every feature states its non-root fallback.

### Phase 4 - Display Lock (2.0.0)

- A profile bound to one TV input: macOS mode (resolution, refresh rate, HDR) plus optional TV
  settings (PC label, picture mode, others found in Phase 3).
- Enforced only while the TV foreground is that input and the display is identified as the TV
  by EDID; no effect on any other input.
- A reducer: observe -> compare -> settle delay -> apply -> verify, all writes through
  `ActionGovernor`. A write that does not stick trips the lock rather than retrying forever.
- HDR enforcement ships only if the spike finds a dependable mechanism; otherwise it is
  detect-and-notify.

### Hardware validation (end of each phase, on the C2)

Pair from scratch, deny pairing, pull the network mid-session, sleep/wake with the TV on another
input and on a streaming app, cold wake, and for Phase 3-4 capture real payloads into fixtures.

## 6. Decisions needed

1. Menu open: reconnect only (proposed) or keep waking the TV.
2. SSH: spawn `/usr/bin/ssh` (no dependency, uses the user's keys and known_hosts; proposed) or
   add a Swift SSH library.
3. HDR: private API allowed if the spike works, or public APIs only.
4. Release shape: four releases as above (proposed) or hold everything for one 2.0.
