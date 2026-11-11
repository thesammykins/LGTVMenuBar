# Architecture

## Layout

```
Sources/LGTVMenuBar/
  Models/      Value types: configuration, connection state, foreground, profiles, errors
  Policies/    Pure decisions, no I/O: PowerPolicy, ActionGovernor, ReconnectSchedule,
               DisplayLockEvaluator
  Protocols/   Seams with a mock or fake behind them
  Services/    I/O and orchestration
  Views/       SwiftUI: MenuBarView, Onboarding, Settings/*, Shared/*
```

`AppDelegate` owns a status item with a popover (`MenuBarView`), the `SettingsWindowController`
(an `NSTabViewController` with toolbar panes), one `TVController` and one `DisplayLockController`.

## Components

| Component | Role |
| --- | --- |
| `WebOSClient` | SSAP over WebSocket. Pairing, request/reply correlation, subscriptions, keep-alive. |
| `TVController` | The app's state and the only place automation runs. Observable by the UI. |
| `PowerPolicy` | Decides what a trigger does, whether sleep powers the TV off, what to do after a wake. |
| `ActionGovernor` | Sliding-window budget per kind of automatic action. |
| `TVReachabilityProbe` | One TCP connect to the SSAP port: "is the TV on?" without waking or pairing. |
| `RootAccessService` | Optional root shell (`SSHRootShell`, `TelnetRootShell`), credentials in the Keychain. |
| `TVPrivilegedCalls` | Calls the pairing connection may not make (settings, input labels): root shell, else notification service. |
| `DisplayService` | macOS display modes (public CoreGraphics) and HDR (SkyLight symbols via `dlsym`). |
| `DisplayLockController` | Holds the display setup to a profile while the TV shows the Mac's input. |

## State machines

### Connection (`WebOSClient`, mirrored read-only by `TVController`)

```
disconnected -> connecting -> registering -> connected
                                 |  ^
                                 v  |
                           awaitingPairing        (TV is showing its prompt)

any state -> error(reason)        socket failure or keep-alive silence
any state -> disconnected         disconnect(), or every endpoint failed
```

- Endpoints are tried in order (`wss:3001`, then `ws:3000`). A pairing refusal or timeout ends
  the attempt without trying the next endpoint, so the TV shows one prompt, not two.
- Each attempt has an id. Callbacks from an older attempt are ignored.
- Registration has two timeouts: 10 s for any answer, then 60 s once the prompt is showing.
- Every request has a 5 s reply timeout. Only the keep-alive (a `getVolume` every 45 s) turns
  silence into a connection failure, and only after two unanswered in a row; an ordinary request
  that times out just throws.

### Reconnect supervision (`TVController.ensureReconnectSupervision`)

Runs whenever a TV is configured, the Mac is awake, pairing does not need the user and the
connection is down. Each check is a TCP probe on `ReconnectSchedule` (2 s doubling to 60 s, then
every 60 s). A full connect follows only when the probe succeeds. It never sends Wake-on-LAN.
The backoff position survives a connection that drops within a minute, so a TV that accepts and
immediately drops is not retried every two seconds. A TV that turns out to be in standby is
released and looked at again after five minutes.

The same release happens on a live session. The client subscribes to the TV's power state
(`subscribePowerState`), and `handlePowerStateChange` drops the connection when the TV reports
standby, because a TV that keeps its network up would otherwise hold the session open and look
connected while off. A wake in progress is left to finish first.

### Wake recovery (`TVController.ensureTVAwake`)

```
trigger -> PowerPolicy.decision -> wake | reconnectOnly | nothing

wake:
  a connect is already in flight?  -> wait for it (never restart a pairing prompt)
  not connected but port answers?  -> connect quietly to look
  connected -> read power state
       on and showing a picture -> stop: no wake, no input switch
       screen off               -> screen on, post-wake actions
       standby, session predates the trigger, nobody at the Mac -> stop (a pixel refresh may be
           running), and watch for input: someone arriving wakes it
       turning off, nobody at the Mac -> stop
       standby or off otherwise -> continue
  governor(.powerOn) refused -> stop
  drop the connection, send Wake-on-LAN
  reconnect until connected or timeout (default 90 s)
  read power state, screen on if needed
       still off (standby, turning off) -> one more wake round, then stop
  post-wake actions (PowerPolicy.postWakeActions): input switch, PC label
```

The input is only ever switched on the path where this app turned the TV on. A TV found on and
showing a picture returns early, so whatever it is showing stays.

One recovery runs at a time. Mac sleep cancels it. A user's Disconnect is sticky: background
reconnects stay off until the user connects or a trigger asks for the TV.

### Sleep (`TVController.handleMacSleep`)

Asks the TV what is in front, then `PowerPolicy.sleepDecision`: power off only when the Mac's
input is in front (or nothing is known); leave the TV on for any other input or app.
The screensaver and the Home screen are ignored as foreground values (`TVForeground.systemSurfaceAppIDs`),
so a TV that fell back to its screensaver when the Mac's display slept is still switched off.

### Panel care (`TVController`, `PanelCarePolicy`)

An OLED TV refreshes its pixels after a few hours of use, but only while switched off. A TV used
as a monitor may never be off long enough, so the refresh falls behind. With root access the app
reads the TV's own state (`com.webos.service.oledepl`: panel hours, how many refreshes have run,
and `isPixelRefresherCondition`) into `PanelCareStatus`. Whether a refresh is due comes only from
the TV's flag; its last-refresh figures are on a different clock from the panel hours and are not
used. The state is read again after each connect, with retries, because the TV's shell is not up
the moment it powers on.

"Use since the last refresh" is the app's own measurement. `PanelCareHistory` notes the panel
hours and the time when the refresh count is first seen to go up, and is kept in UserDefaults
through `PanelCareHistoryStoring`. Until the app has seen one refresh it shows nothing rather
than guess. The "next refresh" estimate is the TV's reported interval (`offrsInterval`, 4 hours
on a C2) less that use; the TV's flag overrides it either way.

`PanelCareSchedule` can limit switching the TV off to hours of the day. It only narrows the
locked-or-asleep rule. A Mac locked before the hours begin is looked at again when they do
(`waitForAllowedHours`); unlocking or waking cancels that.

```
screen locked, or display slept (option on); never while the Mac is unlocked
  -> grace delay (60 s; unlock or wake cancels)
  -> read panel-care state and foreground
  -> PanelCarePolicy.powerOffDecision: locked (macOS is asked directly), inside the set
     hours, due, connected, Mac's input in front?
     outside the set hours -> wait for them to begin, then decide again
  -> governor(.powerOff) -> power off -> quiet period begins

quiet period (pixelRefreshStartedAt set, at most 10 min)
  no reconnect supervision, no quiet reconnects
  poll panel-care state every 30 s
     no longer due / TV stopped answering / window elapsed -> end
  wake trigger -> PanelCarePolicy.wakeDecision
     unlock, menu, app activation, or input within 30 s -> end and wake now
     system or display wake with nobody there           -> hold; wake when the period ends
```

Mac sleep with a refresh due starts the same quiet period after the usual power-off. The TV's
refresh counter is noted when a quiet period begins and compared on the next read, so the log
says whether a refresh actually ran.

### Privileged calls (`TVPrivilegedCalls.invokePrivileged`)

Some services answer "401 insufficient permissions" on the pairing connection: writing settings,
and on current firmware `com.webos.service.eim/setDeviceInfo` (the PC input label). Those go
through the root shell when it is usable, otherwise through the TV's notification service
(create an alert whose close action is the Luna call, then close it).

### Display Lock (`DisplayLockController`)

```
change noted -> settle delay (3 s, restarts on further changes)
  -> evaluate: inactive(reason) | compliant | drift([corrections])
  -> drift: for each correction: governor permit -> apply
  -> verify delay (4 s) -> evaluate again
       compliant  -> done
       same drift -> count a failure; twice for one correction -> paused(reason)
paused -> resume() by the user, or the profile is edited
```

Changes come from the TV's foreground, the connection, the profile, and
`NSApplication.didChangeScreenParametersNotification`. Applying a correction produces those same
events, which is why changes coalesce, writes are budgeted and a correction that will not stick
pauses the lock.

The lock is inactive unless the TV is connected and showing the profile's input.

## Loop guards, in one place

| Risk | Guard |
| --- | --- |
| Wake storms, repeated power off, input flipping | `ActionGovernor`: 6 per kind per 10 min, then 15 min pause, shown in the UI |
| Repeated pairing prompts | `pairingRequiresUser`; one endpoint per refusal |
| Reconnect hammering | Probe before connect; capped backoff; nothing while the Mac sleeps |
| Refresh never completing | Quiet period; unattended wakes held; bounded at 10 min so the TV always comes back |
| Display Lock fighting macOS or the TV | Settle delay, governor, two-strikes pause |
| Hung connect blocking all later wakes | Timer-driven timeouts that do not rely on cancellation |

## Root access

Disabled by default. When enabled, `RootAccessService.run` opens one connection per command.

- SSH: in-process (Citadel). Authentication is an Ed25519 key generated by the app and kept in
  the Keychain, or a password kept in the Keychain. The host key is trusted on first use and
  pinned by SHA-256 fingerprint in the configuration.
- Telnet: plain TCP with minimal option negotiation. Offered because Homebrew Channel exposes it;
  the UI says it is unencrypted.
- Commands are wrapped in begin/done markers (`RootShellFraming`) so output can be separated from
  banners, prompts and echo on either transport. Luna calls validate the URI and shell-quote the
  JSON.

## Configuration and secrets

`TVConfiguration` is JSON in UserDefaults under `tv_configuration`. Decoding is written out so
configurations from older releases load with defaults for newer keys. The webOS client key, the
SSH private key and any shell password are Keychain items.

## Diagnostics

`DiagnosticLogger` is an in-memory ring exported as JSON from Settings › Advanced. Components log
through `TVController.logDiagnostic` with a category (`TVController`, `WebOSClient`,
`RootAccess`, `PrivilegedCalls`, `PanelCare`, `DisplayLock`, `Settings`). The same events go to the unified
log under subsystem `com.lgtvmenubar`.
