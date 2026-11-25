# Hardware validation

Things that were written without a TV to try them on. Check each on real hardware, then delete
the row or record what differed. Turn on "Record a diagnostic log" with "Include routine events"
first, and export the log if anything misbehaves.

## Confirmed on an LG C2 (webOS 7, kernel 5.4.268, firmware as of 2026-11-10)

- Pairing connection over `wss://…:3001`, reconnect after a drop, foreground reporting.
- `ssap://tv/getInputList` does not exist (404). `ssap://com.webos.service.eim/setDeviceInfo`
  and `ssap://com.webos.service.update/getCurrentSWInformation` answer 401 on the pairing
  connection. Releases up to 1.6.2 called all three and ignored the failures.
- Telnet root shell from Homebrew Channel: no login, `uid=0`, `luna-send` present. The probe,
  the picture-mode read (`hdrGame`, with the input reported as `hdmi1_pc`), the power state and
  the panel-care query all return what the parsers expect.
- `luna://com.webos.service.eim/getAllInputStatus` returns the input list with icons and labels.
- `com.webos.service.oledepl` exists and reports panel hours, refresh history and
  `isPixelRefresherCondition`.
- `ssap://tv/getExternalInputList` works on the pairing connection and returns each input's
  label and icon; the icon is a full URL ending in the file name (`…/pc.png`).
- In the app: the root probe's software line (`webOSTV 7.0`, `HE_DTV_W22O_AFABATPU`, firmware
  `33.31.68`), the panel-care query, reconnect after a manual disconnect, and a clean session
  with no rejected requests.
- Pixel refresh: with a refresh due, the Mac slept, the app switched the TV off, and by morning
  the TV's refresh counter had gone from 424 to 425 and `isPixelRefresherCondition` was false.
  The TV's `offrsLastTime` read 6037 while panel hours read 6140, so the two are not on the same
  clock; nothing is derived from the former.
- The TV's Telnet shell refuses connections for a short while after it powers on.
- Lock-triggered refresh (2026-11-11): locked with a refresh due, the app switched the TV off a
  minute later. The shell kept answering for about six minutes with the count unchanged, then
  stopped; on the next connect the count had gone from 425 to 426 and nothing was due.
- Display-sleep lock detection: "Mac downtime began" with reason `displaySlept` and
  `isMacLocked` true was logged with no lock notification.
- Standby with the session held: after the Mac's display slept the TV went into standby by
  itself, the WebSocket session stayed connected for half an hour, and the TV reported
  `Active Standby`. That is ordinary standby on this TV, not a refresh.
- Refresh clocks: two refreshes 10 panel hours apart (6136, 6146) were reported by
  `offrsLastTime` as 8 apart (6037, 6045). `offrsInterval` is 4 and `jbInterval` is 500.
- macOS posts `com.apple.screenIsLocked` for a manual lock but not when the lock comes from the
  display going to sleep.
- The TV occasionally leaves one `getVolume` unanswered on a healthy connection.
- Standby power state (2026-11-23): the power subscription reports `Active Standby` when the TV turns itself off, and the app releases the connection ("TV went into standby - releasing the connection"). With Quick Start+ on, the TV can stay in that state for 40 minutes and more with ports 3000 and 3001 accepting TCP but dropping the WebSocket ("Socket is not connected" on 3001, "The network connection was lost" on 3000).
- The three SkyLight HDR symbols exist on macOS 27.2, and the two read-only ones report the TV
  correctly.
- Screen off and on (2026-11-25): `ssap://com.webos.service.tvpower/power/turnOffScreen` and
  `turnOnScreen` answer 401 on the pairing connection. The same `luna://` calls with
  `{standbyMode: active}` work through the root shell. The power state then reads `Screen Off`
  with the session still connected, and on display wake the app turns the screen on with no
  reconnect. No DCPEXT1, IRQ_HPD or link messages appeared in the kernel log around that wake.
- `NSApplication.didChangeScreenParametersNotification` was not posted for a display sleep and
  wake with the TV's screen off (macOS 27.3), so only the wake notification started Display
  Lock's 30-second hold.

## Written from documentation, not yet tried

| Area | Assumption | How to check |
| --- | --- | --- |
| PC label write | `luna://com.webos.service.eim/setDeviceInfo` with `{id, icon, label}` succeeds from the root shell, and through the notification service without root | Rename HDMI 1 on the TV, turn on "Keep the input labelled as a PC" in Display Lock, and watch it change back. Repeat with root access off. |
| Lock from display sleep | `CGSessionCopyCurrentDictionary` reports `CGSSessionScreenIsLocked` once the display has slept and the password delay has passed | Let the display sleep with a refresh due and the option on. The log shows "Mac downtime began" (displaySlept) and a "Downtime decision" with `isMacLocked` true. |
| Shell during standby | The Telnet shell keeps answering while the TV refreshes | Same test: if the log shows "TV stopped answering" straight away, the quiet period is ending early. |
| Unattended wake | Keyboard and mouse idle time is long on a wake with nobody there | Hard to stage; check the `userIdleSeconds` value in any "Wake held" log line. |
| Mute | `ssap://audio/setMute` works; otherwise the app falls back to `audio/mute` / `audio/unmute` | Mute and unmute from the menu. "Endpoint rejected; retrying its older name" means the fallback ran. |
| Pairing refusal | The TV answers a refused prompt with an `error` frame containing 403 or "rejected" | Forget the pairing on the TV, connect, press Decline. The menu should say "Pairing needed" within a second or two. |
| Pairing prompt | The TV sends a `response` with `pairingType: PROMPT` before `registered` | Same flow; status should read "Accept the prompt on your TV". |
| System surfaces | The screensaver is `com.webos.app.screensaver` and Home is `com.webos.app.home` | Let the Mac's display sleep until the TV shows its screensaver, then sleep the Mac: the TV should turn off. "TV foreground changed" log lines show the real ids. |
| Display sleep screen-off | `screensDidSleepNotification` arrives while an app holds the Mac awake, and a lock-screen notification wakes the display with a long idle time | Leave the Mac idle with Wave Link running until the display sleeps: the log shows "Display asleep - turning TV screen off". A notification overnight should log "Wake held - display woke with nobody at the Mac", and moving the mouse should bring the screen back. |
| Screen off without root | The notification-service route makes `luna://com.webos.service.tvpower/power/turnOffScreen` and `turnOnScreen` work | Turn root access off, let the display sleep and wake. The log shows "Screen command not allowed over the pairing connection; using a privileged call" and no "Screen off refused - powering the TV off instead". |
| Reconfiguration storm | A failing HDMI link posts `didChangeScreenParametersNotification` at least three times, a second or more apart, within a minute | Hard to stage; after a wake where the display drops out, the log shows "Display reconfiguration storm detected; Display Lock holding" and Settings › Display says the display keeps reconnecting. |
| PC label hold after wake | The post-wake label write waits for `DisplayStability` | Rename HDMI 1 on the TV, sleep the Mac until the TV is off, wake it. The log shows "PC label held - display not settled", then "Setting PC label after wake" about 30 s after the wake. |
| Pixel refresh after display sleep | With the screen (not the TV) off, the panel-care path still powers the TV off inside the set hours | Between 01:00 and 06:00 with a refresh due, let the display sleep and lock. A minute later the log shows "Downtime decision" with `powerOff`, then "TV switched off for a pixel refresh". |
| Standby pace for a refusing TV | A TV in network standby keeps accepting TCP on 3000/3001 while it drops the WebSocket, and stays that way until woken | Let the TV go into standby with the Mac awake. After three "Reconnect attempt failed" lines the log shows "TV answers but refuses the session - checking at the standby pace", then one attempt every five minutes. |
| Picture mode read without root | `ssap://settings/getSystemSettings` works on the pairing connection | Display › "Use the TV's Current Mode" with root access off. |
| Picture mode write | Root: `setSystemSettings`. Without root: the notification-service route | Set a picture mode in Display Lock, change it on the TV, watch it return. |
| SSH to the TV | Homebrew Channel's SSH server accepts an Ed25519 user key and an algorithm Citadel offers | Advanced › "Create Key and Install on TV", then Test Connection. |
| HDR switching | `SLSDisplaySetHDRModeEnabled(display, enabled, 0, 0)` changes HDR (the state is read back, the return value ignored) | Lock HDR on, turn HDR off in System Settings. It should return within about ten seconds, or the lock pauses after two tries. |
| Display mode | `CGConfigureDisplayWithDisplayMode` with a 120 Hz mode holds on this TV | Lock the mode, change refresh rate in System Settings, watch it return. |

## Scenarios to run before a release

1. Pair from scratch, and again after declining once.
2. Pull the TV's network cable while connected; plug it back in. The app reconnects by itself.
3. Sleep and wake the Mac with the TV on the Mac's input.
4. Sleep and wake the Mac with the TV on another input, and on a streaming app. The TV is left
   alone both times, and the input is not switched on wake.
5. Turn the TV off with its remote, then wake the Mac.
6. With a second display attached and the TV off, open the menu with "Also when opening the
   menu" on and off.
7. Lock the display mode and HDR; change each in System Settings; switch the TV to another
   input and change them again (nothing should be put back).
8. With a pixel refresh due and the option on, lock the Mac and leave it for ten minutes; the
   refresh should complete. Repeat, but unlock after two minutes: the TV comes straight back.
9. Let the Mac's display sleep until the TV turns itself off, then wake and unlock the Mac: the
   TV should be sent a wake ("Wake-on-LAN attempt"), not left in standby.
10. While connected, turn the TV off with its remote. Within a few seconds the log should show
   "TV went into standby - releasing the connection" and the menu should offer Turn On. This
   depends on the TV pushing power-state changes over `ssap://com.webos.service.tvpower/power/getPowerState`,
   which has not been seen on hardware yet.
11. Set Panel Care to "Only during set hours" with hours that exclude now, and lock the Mac with
   a refresh due: "Downtime decision" should say `outside the set hours` and the TV stays on.
