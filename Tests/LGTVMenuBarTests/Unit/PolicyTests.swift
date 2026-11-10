import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("ActionGovernor")
struct ActionGovernorTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let limit = ActionGovernor.Limit(maxActions: 3, window: 60, cooldown: 300)

    @Test("allows actions up to the limit, then trips")
    func tripsAtLimit() {
        var governor = ActionGovernor(limits: [.powerOn: limit])
        for offset in 0..<3 {
            #expect(governor.request(.powerOn, now: start.addingTimeInterval(Double(offset))) == .allowed)
        }
        #expect(governor.request(.powerOn, now: start.addingTimeInterval(3)) == .tripped(until: start.addingTimeInterval(303)))
        #expect(governor.trippedKinds(now: start.addingTimeInterval(4)) == [.powerOn])
    }

    @Test("stays tripped during cooldown even when the window has passed")
    func staysTrippedDuringCooldown() {
        var governor = ActionGovernor(limits: [.powerOn: limit])
        for offset in 0..<4 { _ = governor.request(.powerOn, now: start.addingTimeInterval(Double(offset))) }
        #expect(!governor.request(.powerOn, now: start.addingTimeInterval(120)).isAllowed)
    }

    @Test("recovers after cooldown")
    func recoversAfterCooldown() {
        var governor = ActionGovernor(limits: [.powerOn: limit])
        for offset in 0..<4 { _ = governor.request(.powerOn, now: start.addingTimeInterval(Double(offset))) }
        #expect(governor.request(.powerOn, now: start.addingTimeInterval(400)) == .allowed)
        #expect(governor.trippedKinds(now: start.addingTimeInterval(400)).isEmpty)
    }

    @Test("old actions fall out of the sliding window")
    func slidingWindow() {
        var governor = ActionGovernor(limits: [.inputSwitch: limit])
        for offset in [0.0, 30, 59] { #expect(governor.request(.inputSwitch, now: start.addingTimeInterval(offset)).isAllowed) }
        #expect(governor.request(.inputSwitch, now: start.addingTimeInterval(61)).isAllowed)
    }

    @Test("kinds are budgeted independently")
    func independentKinds() {
        var governor = ActionGovernor(limits: [.powerOn: limit, .powerOff: limit])
        for offset in 0..<4 { _ = governor.request(.powerOn, now: start.addingTimeInterval(Double(offset))) }
        #expect(governor.request(.powerOff, now: start.addingTimeInterval(5)).isAllowed)
    }

    @Test("manual reset clears a trip")
    func manualReset() {
        var governor = ActionGovernor(limits: [.powerOn: limit])
        for offset in 0..<4 { _ = governor.request(.powerOn, now: start.addingTimeInterval(Double(offset))) }
        governor.reset()
        #expect(governor.request(.powerOn, now: start.addingTimeInterval(5)).isAllowed)
    }
}

@Suite("ReconnectSchedule")
struct ReconnectScheduleTests {
    @Test("backs off from two seconds and caps at one minute")
    func backoff() {
        #expect(ReconnectSchedule.delay(forAttempt: 0) == .seconds(2))
        #expect(ReconnectSchedule.delay(forAttempt: 1) == .seconds(4))
        #expect(ReconnectSchedule.delay(forAttempt: 4) == .seconds(32))
        #expect(ReconnectSchedule.delay(forAttempt: 5) == .seconds(60))
        #expect(ReconnectSchedule.delay(forAttempt: 500) == .seconds(60))
        #expect(ReconnectSchedule.delay(forAttempt: -3) == .seconds(2))
    }

    @Test("logging thins out for long outages")
    func logging() {
        #expect(ReconnectSchedule.shouldLog(attempt: 0))
        #expect(ReconnectSchedule.shouldLog(attempt: 3))
        #expect(!ReconnectSchedule.shouldLog(attempt: 5))
        #expect(ReconnectSchedule.shouldLog(attempt: 64))
    }
}

@Suite("PowerPolicy")
struct PowerPolicyTests {
    private func config(
        wakeWithMac: Bool = true,
        sleepWithMac: Bool = true,
        switchInputOnWake: Bool = true,
        enablePCMode: Bool = false,
        wakeOnMenuOpen: Bool = true
    ) -> TVConfiguration {
        TVConfiguration(
            name: "TV", ipAddress: "10.0.0.2", macAddress: "AA:BB:CC:DD:EE:FF", preferredInput: "HDMI_1",
            wakeWithMac: wakeWithMac, sleepWithMac: sleepWithMac, switchInputOnWake: switchInputOnWake,
            enablePCMode: enablePCMode, wakeOnMenuOpen: wakeOnMenuOpen
        )
    }

    @Test("system wake, screen wake and unlock wake the TV when enabled", arguments: [PowerPolicy.Trigger.systemWake, .screenWake, .screenUnlock])
    func wakeTriggers(trigger: PowerPolicy.Trigger) {
        #expect(PowerPolicy.decision(for: trigger, config: config(), isConnected: false) == .wake)
        #expect(PowerPolicy.decision(for: trigger, config: config(wakeWithMac: false), isConnected: false) == .reconnectOnly)
        #expect(PowerPolicy.decision(for: trigger, config: config(wakeWithMac: false), isConnected: true) == .nothing)
    }

    @Test("opening the menu wakes only when both settings allow it")
    func menuOpened() {
        #expect(PowerPolicy.decision(for: .menuOpened, config: config(), isConnected: false) == .wake)
        #expect(PowerPolicy.decision(for: .menuOpened, config: config(wakeOnMenuOpen: false), isConnected: false) == .reconnectOnly)
        #expect(PowerPolicy.decision(for: .menuOpened, config: config(wakeWithMac: false), isConnected: false) == .reconnectOnly)
        #expect(PowerPolicy.decision(for: .menuOpened, config: config(wakeOnMenuOpen: false), isConnected: true) == .nothing)
    }

    @Test("activating the app never powers the TV on")
    func appActivated() {
        #expect(PowerPolicy.decision(for: .appActivated, config: config(), isConnected: false) == .reconnectOnly)
        #expect(PowerPolicy.decision(for: .appActivated, config: config(), isConnected: true) == .nothing)
    }

    @Test("a user request always wakes")
    func userRequested() {
        #expect(PowerPolicy.decision(for: .userRequested, config: config(wakeWithMac: false), isConnected: false) == .wake)
    }

    @Test("sleep powers off only when the Mac's input is in front")
    func sleepDecision() {
        #expect(PowerPolicy.sleepDecision(config: config(), isConnected: true, foreground: .input(.hdmi1)) == .powerOff)
        #expect(PowerPolicy.sleepDecision(config: config(), isConnected: true, foreground: .unknown) == .powerOff)
        #expect(PowerPolicy.sleepDecision(config: config(), isConnected: true, foreground: .input(.hdmi2)) == .leaveOn(reason: "TV is on HDMI 2"))
        #expect(PowerPolicy.sleepDecision(config: config(), isConnected: true, foreground: .app("netflix")) == .leaveOn(reason: "TV is showing netflix"))
        #expect(PowerPolicy.sleepDecision(config: config(), isConnected: false, foreground: .input(.hdmi1)) == .skip(reason: "not connected to the TV"))
        #expect(PowerPolicy.sleepDecision(config: config(sleepWithMac: false), isConnected: true, foreground: .input(.hdmi1)) == .skip(reason: "sleep automation disabled"))
    }

    @Test("input is switched once the app has powered the TV on")
    func switchAfterPowerOn() {
        let actions = PowerPolicy.postWakeActions(config: config(), foreground: .input(.hdmi2), preferredInputIsPCMode: false)
        #expect(actions.switchInput)
    }

    @Test("no switch when already on the preferred input or when the option is off")
    func noRedundantSwitch() {
        #expect(!PowerPolicy.postWakeActions(config: config(), foreground: .input(.hdmi1), preferredInputIsPCMode: false).switchInput)
        #expect(!PowerPolicy.postWakeActions(config: config(switchInputOnWake: false), foreground: .input(.hdmi2), preferredInputIsPCMode: false).switchInput)
    }

    @Test("PC mode is written only when wanted and not already set")
    func pcMode() {
        #expect(PowerPolicy.postWakeActions(config: config(enablePCMode: true), foreground: .unknown, preferredInputIsPCMode: false).setPCMode)
        #expect(!PowerPolicy.postWakeActions(config: config(enablePCMode: true), foreground: .unknown, preferredInputIsPCMode: true).setPCMode)
        #expect(!PowerPolicy.postWakeActions(config: config(enablePCMode: false), foreground: .unknown, preferredInputIsPCMode: false).setPCMode)
    }

    @Test("an unknown preferred input produces no actions")
    func unknownPreferredInput() {
        var broken = config(enablePCMode: true)
        broken.preferredInput = "COMPONENT_9"
        #expect(PowerPolicy.postWakeActions(config: broken, foreground: .unknown, preferredInputIsPCMode: false) == .none)
    }
}

@Suite("TVForeground")
struct TVForegroundTests {
    @Test("input apps map to inputs, other apps stay apps, empty ids are ignored")
    func mapping() {
        #expect(TVForeground.from(appId: "com.webos.app.hdmi2") == .input(.hdmi2))
        #expect(TVForeground.from(appId: "COM.WEBOS.APP.HDMI1") == .input(.hdmi1))
        #expect(TVForeground.from(appId: "netflix") == .app("netflix"))
        #expect(TVForeground.from(appId: "com.webos.app.livetv") == .app("com.webos.app.livetv"))
        #expect(TVForeground.from(appId: "") == nil)
        #expect(TVForeground.from(appId: "  ") == nil)
    }

    @Test("the screensaver and home screen are not a viewing choice")
    func systemSurfaces() {
        #expect(TVForeground.from(appId: "com.webos.app.screensaver") == nil)
        #expect(TVForeground.from(appId: "com.webos.app.home") == nil)
    }

    @Test("the PC label is read from the icon's file name, bare or as a URL")
    func pcIcon() {
        #expect(TVInputInfo.iconIndicatesPC("pc.png"))
        #expect(TVInputInfo.iconIndicatesPC("https://192.168.88.56:3001/resources/47d0d0c6009f359613c8f87fe594e60b4d76f063/pc.png"))
        #expect(!TVInputInfo.iconIndicatesPC("https://192.168.88.56:3001/resources/e7be2ea20615eb4ef4a5c8a1ed71b4cd33bcb59f/HDMI_2.png"))
        #expect(!TVInputInfo.iconIndicatesPC("https://pc.local:3001/resources/abc/streamingbox.png"))
        #expect(!TVInputInfo.iconIndicatesPC(""))
    }

    @Test("only inputs expose an input")
    func inputAccessor() {
        #expect(TVForeground.input(.hdmi3).input == .hdmi3)
        #expect(TVForeground.app("youtube").input == nil)
        #expect(TVForeground.unknown.input == nil)
    }
}

@Suite("TVConfiguration migration")
struct TVConfigurationMigrationTests {
    @Test("a 1.6 configuration decodes with defaults for newer fields")
    func decodesLegacyConfiguration() throws {
        let legacy = """
        {"id":"7D8E9F10-1111-2222-3333-444455556666","name":"LG C2","ipAddress":"192.168.1.20","macAddress":"AA:BB:CC:DD:EE:FF",
         "preferredInput":"HDMI_2","autoConnectOnLaunch":true,"wakeWithMac":false,"sleepWithMac":true,"switchInputOnWake":true,
         "enablePCMode":true,"wakePort":9}
        """
        let config = try JSONDecoder().decode(TVConfiguration.self, from: Data(legacy.utf8))
        #expect(config.preferredInput == "HDMI_2")
        #expect(config.wakeWithMac == false)
        #expect(config.wakePort == 9)
        #expect(config.wakeOnMenuOpen == true)
        #expect(config.rootAccess == RootAccessSettings())
        #expect(config.displayLock == DisplayLockProfile())
    }

    @Test("new fields survive a round trip")
    func roundTrip() throws {
        var config = TVConfiguration(name: "TV", ipAddress: "10.0.0.2", macAddress: "AA:BB:CC:DD:EE:FF")
        config.wakeOnMenuOpen = false
        config.rootAccess = RootAccessSettings(isEnabled: true, transport: .telnet, hostOverride: "10.0.0.9", port: 2323, username: "root", authentication: .password)
        config.displayLock = DisplayLockProfile(
            isEnabled: true, inputID: "HDMI_1", displayUUID: "ABC",
            mode: DisplayModeSpec(pixelWidth: 3840, pixelHeight: 2160, pointWidth: 1920, pointHeight: 1080, refreshRate: 120),
            hdrEnabled: true, enforcePCMode: true, pictureMode: "game"
        )
        let decoded = try JSONDecoder().decode(TVConfiguration.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}
